// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

// Builds and runs the native test of the test package aud_test_nodes - the
// only native code of the umbrella (ticket 22), a DSP package the Dart tests
// load as a library of its own - with the address and the
// undefined behaviour sanitizer, and with Clang's RealtimeSanitizer when a
// compiler on this machine has it, with a probe that proves the run
// catches an allocation on the audio thread.
//
//   node scripts/test-native.js               every build this machine has
//   node scripts/test-native.js --no-sanitize  one build, no sanitizer
//   node scripts/test-native.js --library      builds the package as a
//                                              shared library for the Dart
//                                              tests and prints its path

'use strict';

const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const sanitize = !process.argv.includes('--no-sanitize');

// The `src` directory of a package, resolved through the package config.
function packageSrc(name) {
  const configPath = path.join(root, '.dart_tool', 'package_config.json');
  if (!fs.existsSync(configPath)) {
    throw new Error(`Run flutter pub get first: ${configPath} is missing`);
  }
  const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  const entry = config.packages.find((p) => p.name === name);
  if (!entry) throw new Error(`Package ${name} is not in the package config`);
  const rootUri = new URL(entry.rootUri, `file://${configPath}`);
  return path.join(decodeURIComponent(rootUri.pathname), 'src');
}

// Whether `compiler` builds a program with `flags`.
function works(compiler, flags) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'aud-probe-'));
  try {
    const source = path.join(dir, 'probe.cpp');
    fs.writeFileSync(source, 'int main() { return 0; }\n');
    const result = spawnSync(
      compiler,
      [...flags, source, '-o', path.join(dir, 'probe')],
      { encoding: 'utf8' },
    );
    return result.status === 0;
  } catch {
    return false;
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

function rtsanCompiler() {
  for (const candidate of [
    process.env.AUD_RTSAN_CXX,
    '/opt/homebrew/opt/llvm/bin/clang++',
    '/usr/local/opt/llvm/bin/clang++',
  ].filter(Boolean)) {
    if (works(candidate, ['-fsanitize=realtime'])) return candidate;
  }
  return null;
}

// Builds and runs one variant; returns its output or throws.
function run(name, compiler, flags) {
  const outDir = fs.mkdtempSync(path.join(os.tmpdir(), 'aud-native-'));
  const binary = path.join(outDir, `aud_test_nodes_test_${name}`);
  try {
    const build = spawnSync(
      compiler,
      [
        ...flags,
        '-std=c++17',
        '-g',
        '-O1',
        '-Wall',
        '-Wextra',
        '-Werror',
        '-fno-omit-frame-pointer',
        '-I',
        packageSrc('aud_audio_core'),
        path.join(root, 'test_packages/aud_test_nodes/src/aud_test_nodes.cpp'),
        path.join(root, 'test/native/aud_test_nodes_test.cpp'),
        '-o',
        binary,
      ],
      { encoding: 'utf8' },
    );
    if (build.status !== 0) {
      throw new Error(`${name}: build failed\n${build.stdout}${build.stderr}`);
    }
    const test = spawnSync(binary, [], {
      encoding: 'utf8',
      env: {
        ...process.env,
        ASAN_OPTIONS: 'halt_on_error=1',
        UBSAN_OPTIONS: 'halt_on_error=1:print_stacktrace=1',
      },
    });
    const output = `${test.stdout}${test.stderr}`;
    if (test.status !== 0) throw new Error(`${name}: failed\n${output}`);
    return output;
  } finally {
    fs.rmSync(outDir, { recursive: true, force: true });
  }
}

// Builds the test package as a shared library under .dart_tool, as a
// package built apart from the engine; returns its path.
function library() {
  const outDir = path.join(root, '.dart_tool', 'aud_test_nodes');
  fs.mkdirSync(outDir, { recursive: true });
  const ext = process.platform === 'darwin' ? 'dylib' : 'so';
  const out = path.join(outDir, `libaud_test_nodes.${ext}`);
  const source = path.join(
    root,
    'test_packages/aud_test_nodes/src/aud_test_nodes.cpp',
  );
  if (
    fs.existsSync(out) &&
    fs.statSync(out).mtimeMs > fs.statSync(source).mtimeMs
  ) {
    return out;
  }
  const build = spawnSync(
    'clang++',
    [
      '-std=c++17',
      '-O2',
      '-shared',
      '-fPIC',
      '-fvisibility=hidden',
      '-I',
      packageSrc('aud_audio_core'),
      source,
      '-o',
      out,
    ],
    { encoding: 'utf8' },
  );
  if (build.status !== 0) {
    throw new Error(`library: build failed\n${build.stdout}${build.stderr}`);
  }
  return out;
}

function main() {
  if (process.argv.includes('--library')) {
    process.stdout.write(`${library()}\n`);
    return;
  }
  const builds = [];
  if (!sanitize) {
    builds.push(['plain', 'clang++', []]);
  } else {
    // LeakSanitizer is not supported by Apple's clang on arm64.
    builds.push([
      'asan_ubsan',
      'clang++',
      ['-fsanitize=address,undefined', '-fno-sanitize-recover=all'],
    ]);
    const rtsan = rtsanCompiler();
    if (rtsan) {
      builds.push(['rtsan', rtsan, ['-fsanitize=realtime', '-Wno-function-effects']]);
    }
  }
  for (const [name, compiler, flags] of builds) {
    const output = run(name, compiler, flags);
    process.stdout.write(`${name}: ${output}`);
    if (name !== 'rtsan') continue;
    let caught = false;
    try {
      run('rtsan_probe', compiler, [...flags, '-DAUD_RTSAN_PROBE']);
    } catch (error) {
      caught = /RealtimeSanitizer/.test(error.message);
    }
    if (!caught) throw new Error('rtsan: the probe was not caught');
    process.stdout.write('rtsan_probe: caught\n');
  }
}

try {
  main();
} catch (error) {
  process.stderr.write(`${error.message}\n`);
  process.exit(1);
}
