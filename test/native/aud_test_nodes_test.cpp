// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

// The native test of the test package aud_test_nodes: registers it with a
// host of its own, renders its node and checks that the package of the
// future ABI major is refused. scripts/test-native.js builds it with the
// sanitizers.

#include <cstdio>
#include <cstring>
#include <vector>

#include "aud_abi.h"

// The RealtimeSanitizer checks what runs inside a nonblocking function.
#if defined(__has_feature)
#if __has_feature(realtime_sanitizer)
#define AUD_REALTIME [[clang::nonblocking]]
#endif
#endif
#ifndef AUD_REALTIME
#define AUD_REALTIME
#endif

extern "C" int32_t aud_test_nodes_register(const AudHostApi* host);
extern "C" int32_t aud_test_nodes_future_register(const AudHostApi* host);

namespace {

int checks = 0;
int failed = 0;

void check(bool condition, const char* what) {
  ++checks;
  if (!condition) {
    ++failed;
    std::printf("FAILED: %s\n", what);
  }
}

// Calls process as the audio thread does.
void processRealtime(const AudNodeVTable* vtable, void* node,
                     const AudProcessContext* context) AUD_REALTIME {
#ifdef AUD_RTSAN_PROBE
  int* volatile probe = new int(1);  // RTSan must catch this allocation
  delete probe;
#endif
  vtable->process(node, context);
}

// A host that keeps the registered descriptors and refuses other majors.
struct Host {
  std::vector<const AudNodeDescriptor*> types;
};

int32_t registerNodeType(void* host, const AudNodeDescriptor* descriptor) {
  if (descriptor->abi_major != AUD_ABI_VERSION_MAJOR) {
    return AUD_ERROR_ABI_MAJOR;
  }
  static_cast<Host*>(host)->types.push_back(descriptor);
  return AUD_OK;
}

AudHostApi hostApi(Host* host) {
  AudHostApi api = {};
  api.struct_size = sizeof(AudHostApi);
  api.abi_major = AUD_ABI_VERSION_MAJOR;
  api.abi_minor = AUD_ABI_VERSION_MINOR;
  api.abi_oldest_minor = AUD_ABI_VERSION_MINOR;
  api.host = host;
  api.register_node_type = registerNodeType;
  return api;
}

void testRegister() {
  Host host;
  const AudHostApi api = hostApi(&host);
  check(aud_test_nodes_register(&api) == AUD_OK, "register returns AUD_OK");
  check(host.types.size() == 1, "one node type is registered");
  check(std::strcmp(host.types[0]->type_id, "aud.test.invert") == 0,
        "the type is aud.test.invert");
  check(aud_test_nodes_register(nullptr) == AUD_ERROR_INVALID_ARGUMENT,
        "a missing host is refused");
}

void testFutureAbi() {
  Host host;
  const AudHostApi api = hostApi(&host);
  check(aud_test_nodes_future_register(&api) == AUD_ERROR_ABI_MAJOR,
        "a future ABI major is refused");
  check(host.types.empty(), "nothing is registered");
}

void testRender() {
  Host host;
  const AudHostApi api = hostApi(&host);
  aud_test_nodes_register(&api);
  const AudNodeDescriptor* type = host.types[0];
  void* node = type->vtable->create(type, &api);
  check(node != nullptr, "create returns an instance");
  AudPrepareInfo info = {};
  info.struct_size = sizeof(AudPrepareInfo);
  info.sample_rate = 48000;
  info.max_frames = 64;
  check(type->vtable->prepare(node, &info) == AUD_OK, "prepare succeeds");

  std::vector<float> input(64), output(64);
  for (size_t i = 0; i < input.size(); ++i) input[i] = 0.01f * i;
  float* inChannels[] = {input.data()};
  float* outChannels[] = {output.data()};
  AudAudioBus in = {};
  in.struct_size = sizeof(AudAudioBus);
  in.num_channels = 1;
  in.channels = inChannels;
  AudAudioBus out = in;
  out.channels = outChannels;
  AudProcessContext context = {};
  context.struct_size = sizeof(AudProcessContext);
  context.frames = 64;
  context.num_input_buses = 1;
  context.num_output_buses = 1;
  context.inputs = &in;
  context.outputs = &out;
  processRealtime(type->vtable, node, &context);
  bool inverted = true;
  for (size_t i = 0; i < output.size(); ++i) {
    inverted = inverted && output[i] == -input[i];
  }
  check(inverted, "the node inverts its input");
  type->vtable->destroy(node);
}

}  // namespace

int main() {
  testRegister();
  testFutureAbi();
  testRender();
  std::printf("%d checks, %d checks failed\n", checks, failed);
  return failed == 0 ? 0 : 1;
}
