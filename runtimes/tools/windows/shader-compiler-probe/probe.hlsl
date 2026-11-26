// Synthetic reproducer derived only from the local authored reference fixture.
#ifndef THREADS
#define THREADS 1
#endif
cbuffer UserData : register(b0) { uint base; };
#if defined(TYPED_SOURCE)
#define SOURCE_TYPE Buffer<uint>
#elif defined(UAV_SOURCE)
#define SOURCE_TYPE RWByteAddressBuffer
#else
#define SOURCE_TYPE ByteAddressBuffer
#endif
#if defined(MIXED_QUERY_TABLE) || defined(MIXED_LOAD_TABLE)
#ifdef UAV_SOURCE
SOURCE_TYPE tableSources[] : register(u0);
#else
SOURCE_TYPE tableSources[] : register(t0);
#endif
#endif
#ifdef EXPLICIT_ARRAY
#ifdef FINITE_ARRAY
#define ARRAY_COUNT 16
#else
#define ARRAY_COUNT
#endif
#ifdef UAV_SOURCE
SOURCE_TYPE sources[ARRAY_COUNT] : register(u1);
#else
SOURCE_TYPE sources[ARRAY_COUNT] : register(t0);
#endif
RWByteAddressBuffer dest : register(u0);
#elif defined(EXPLICIT_REGISTERS)
SOURCE_TYPE source : register(t0);
RWByteAddressBuffer dest : register(u0);
#endif
#if defined(WAVE64)
[WaveSize(64)]
#elif defined(WAVE32)
[WaveSize(32)]
#endif
[numthreads(THREADS, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint sourceIndex = base >> 5;
#ifdef VARYING_INDEX
    sourceIndex += tid.x;
#endif
#ifdef EXPLICIT_ARRAY
    SOURCE_TYPE source = sources[sourceIndex];
#else
#ifndef EXPLICIT_REGISTERS
#ifdef NONUNIFORM_INDEX
    SOURCE_TYPE source = ResourceDescriptorHeap[NonUniformResourceIndex(sourceIndex)];
    RWByteAddressBuffer dest = ResourceDescriptorHeap[NonUniformResourceIndex((base + 64) >> 5)];
#else
#ifdef NONUNIFORM_SOURCE
    SOURCE_TYPE source = ResourceDescriptorHeap[NonUniformResourceIndex(sourceIndex)];
#else
    SOURCE_TYPE source = ResourceDescriptorHeap[sourceIndex];
#endif
    RWByteAddressBuffer dest = ResourceDescriptorHeap[(base + 64) >> 5];
#endif
#endif
#endif
#ifdef NO_DIMENSIONS
    uint bytes = 48;
#else
    uint bytes;
#ifdef QUERY_LANE_IDENTITY
    uint queryIndex = WaveReadLaneAt(sourceIndex, WaveGetLaneIndex());
    SOURCE_TYPE dimensionSource = ResourceDescriptorHeap[NonUniformResourceIndex(queryIndex)];
    dimensionSource.GetDimensions(bytes);
#elif defined(MIXED_QUERY_TABLE)
    SOURCE_TYPE dimensionSource = tableSources[sourceIndex];
    dimensionSource.GetDimensions(bytes);
#elif defined(DIMENSION_WAVE_INDEX)
    SOURCE_TYPE dimensionSource = ResourceDescriptorHeap[NonUniformResourceIndex(WaveReadLaneFirst(base) >> 5)];
    dimensionSource.GetDimensions(bytes);
#elif defined(DIMENSION_NONUNIFORM)
    SOURCE_TYPE dimensionSource = ResourceDescriptorHeap[NonUniformResourceIndex(sourceIndex)];
    dimensionSource.GetDimensions(bytes);
#elif defined(DIMENSION_UNIFORM)
    SOURCE_TYPE dimensionSource = ResourceDescriptorHeap[sourceIndex];
    dimensionSource.GetDimensions(bytes);
#else
    source.GetDimensions(bytes);
#endif
#endif
#ifdef NO_LOAD
    uint loaded = 0;
#else
#ifdef MIXED_LOAD_TABLE
    SOURCE_TYPE loadSource = tableSources[sourceIndex];
    uint loaded = loadSource.Load(0);
#elif defined(LOAD_WAVE_INDEX)
    SOURCE_TYPE loadSource = ResourceDescriptorHeap[NonUniformResourceIndex(WaveReadLaneFirst(base) >> 5)];
    uint loaded = loadSource.Load(0);
#else
    uint loaded = source.Load(0);
#endif
#endif
#if defined(NO_WAVE)
    uint value = loaded;
#elif defined(LANE_AT_ZERO)
    uint value = WaveReadLaneAt(loaded, 0);
#elif defined(LANE_AT_FIRST_ACTIVE)
    uint4 active = WaveActiveBallot(true);
    uint first = active.x ? firstbitlow(active.x) :
                 active.y ? 32u + firstbitlow(active.y) :
                 active.z ? 64u + firstbitlow(active.z) : 96u + firstbitlow(active.w);
    uint value = WaveReadLaneAt(loaded, first);
#else
    uint value = WaveReadLaneFirst(loaded);
#endif
    dest.Store(0, bytes / 16);
    dest.Store(4, value);
}
