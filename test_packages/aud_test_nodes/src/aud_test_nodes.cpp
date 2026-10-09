// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

// A DSP package built apart from the engine, as a third-party package would
// be: one node type, aud.test.invert, and a second register function that
// claims a future ABI major, which the engine must refuse (abi-001).

#include <algorithm>

#include "aud_abi.h"
#include "aud_node_base.hpp"

namespace {

// Inverts the polarity of its input.
class AudTestInvert : public AudNodeBase {
 public:
  AudTestInvert(const AudNodeDescriptor*, const AudHostApi*)
      : AudNodeBase(0) {}

 protected:
  void renderRange(const AudProcessContext& context, uint32_t offset,
                   uint32_t frames) override {
    if (context.num_input_buses < 1 || context.num_output_buses < 1) return;
    const AudAudioBus& in = context.inputs[0];
    const AudAudioBus& out = context.outputs[0];
    const uint32_t channels = std::min(in.num_channels, out.num_channels);
    for (uint32_t c = 0; c < channels; ++c) {
      const float* source = in.channels[c] + offset;
      float* target = out.channels[c] + offset;
      for (uint32_t i = 0; i < frames; ++i) target[i] = -source[i];
    }
  }
};

const AudBusDescriptor kInputBuses[] = {
    {sizeof(AudBusDescriptor), "in", "Input", AUD_BUS_MAIN, 1, 16, 2},
};

const AudBusDescriptor kOutputBuses[] = {
    {sizeof(AudBusDescriptor), "out", "Output", AUD_BUS_MAIN, 1, 16, 2},
};

const AudNodeVTable kVTable = AudNodeVTableFor<AudTestInvert>::vtable();

AudNodeDescriptor descriptor(uint32_t abiMajor) {
  return {
      sizeof(AudNodeDescriptor),
      abiMajor,
      AUD_ABI_VERSION_MINOR,
      1,  // version
      "aud.test.invert",
      "Invert",
      "Audanika",
      AUD_NODE_CAP_IN_PLACE | AUD_NODE_CAP_VARIABLE_BLOCK,
      0,
      1,
      1,
      kInputBuses,
      kOutputBuses,
      0,
      0,
      nullptr,
      nullptr,
      0,
      0,
      nullptr,
      nullptr,
      &kVTable,
  };
}

const AudNodeDescriptor kInvert = descriptor(AUD_ABI_VERSION_MAJOR);
const AudNodeDescriptor kFutureInvert = descriptor(AUD_ABI_VERSION_MAJOR + 1);

int32_t registerType(const AudHostApi* host, const AudNodeDescriptor* type) {
  if (!host || host->struct_size < sizeof(AudHostApi) ||
      !host->register_node_type) {
    return AUD_ERROR_INVALID_ARGUMENT;
  }
  return host->register_node_type(host->host, type);
}

}  // namespace

extern "C" {

// Registers aud.test.invert, built against the ABI of the engine.
AUD_EXPORT int32_t aud_test_nodes_register(const AudHostApi* host) {
  return registerType(host, &kInvert);
}

// Registers aud.test.invert as a package built against the next ABI major
// would; the engine refuses it with AUD_ERROR_ABI_MAJOR.
AUD_EXPORT int32_t aud_test_nodes_future_register(const AudHostApi* host) {
  return registerType(host, &kFutureInvert);
}

}  // extern "C"
