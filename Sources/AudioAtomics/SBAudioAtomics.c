#include "SBAudioAtomics.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

struct SBAtomicU64 { _Atomic uint64_t value; };
struct SBAtomicU32 { _Atomic uint32_t value; };
struct SBAtomicFloat { _Atomic uint32_t bits; };
struct SBAtomicDouble { _Atomic uint64_t bits; };
struct SBAtomicBool { _Atomic _Bool value; };
struct SBAtomicPointer { _Atomic uintptr_t value; };

struct SBMessageQueue {
    size_t capacity;
    SBAtomicMessage *messages;
    _Atomic uint64_t writeIndex;
    _Atomic uint64_t readIndex;
};

SBAtomicU64 *SBAtomicU64Create(uint64_t value) {
    SBAtomicU64 *atomic = malloc(sizeof(*atomic));
    if (atomic) atomic_init(&atomic->value, value);
    return atomic;
}
void SBAtomicU64Destroy(SBAtomicU64 *atomic) { free(atomic); }
uint64_t SBAtomicU64LoadAcquire(const SBAtomicU64 *atomic) {
    return atomic_load_explicit(&atomic->value, memory_order_acquire);
}
uint64_t SBAtomicU64LoadRelaxed(const SBAtomicU64 *atomic) {
    return atomic_load_explicit(&atomic->value, memory_order_relaxed);
}
void SBAtomicU64StoreRelease(SBAtomicU64 *atomic, uint64_t value) {
    atomic_store_explicit(&atomic->value, value, memory_order_release);
}
void SBAtomicU64StoreRelaxed(SBAtomicU64 *atomic, uint64_t value) {
    atomic_store_explicit(&atomic->value, value, memory_order_relaxed);
}
uint64_t SBAtomicU64FetchAddRelaxed(SBAtomicU64 *atomic, uint64_t value) {
    return atomic_fetch_add_explicit(&atomic->value, value, memory_order_relaxed);
}
void SBAtomicU64MaxRelaxed(SBAtomicU64 *atomic, uint64_t value) {
    uint64_t current = atomic_load_explicit(&atomic->value, memory_order_relaxed);
    while (current < value &&
           !atomic_compare_exchange_weak_explicit(
               &atomic->value,
               &current,
               value,
               memory_order_relaxed,
               memory_order_relaxed
           )) {}
}

SBAtomicU32 *SBAtomicU32Create(uint32_t value) {
    SBAtomicU32 *atomic = malloc(sizeof(*atomic));
    if (atomic) atomic_init(&atomic->value, value);
    return atomic;
}
void SBAtomicU32Destroy(SBAtomicU32 *atomic) { free(atomic); }
uint32_t SBAtomicU32LoadAcquire(const SBAtomicU32 *atomic) {
    return atomic_load_explicit(&atomic->value, memory_order_acquire);
}
void SBAtomicU32StoreRelease(SBAtomicU32 *atomic, uint32_t value) {
    atomic_store_explicit(&atomic->value, value, memory_order_release);
}

SBAtomicFloat *SBAtomicFloatCreate(float value) {
    SBAtomicFloat *atomic = malloc(sizeof(*atomic));
    if (atomic) {
        uint32_t bits;
        memcpy(&bits, &value, sizeof(bits));
        atomic_init(&atomic->bits, bits);
    }
    return atomic;
}
void SBAtomicFloatDestroy(SBAtomicFloat *atomic) { free(atomic); }
float SBAtomicFloatLoadRelaxed(const SBAtomicFloat *atomic) {
    uint32_t bits = atomic_load_explicit(&atomic->bits, memory_order_relaxed);
    float value;
    memcpy(&value, &bits, sizeof(value));
    return value;
}
void SBAtomicFloatStoreRelaxed(SBAtomicFloat *atomic, float value) {
    uint32_t bits;
    memcpy(&bits, &value, sizeof(bits));
    atomic_store_explicit(&atomic->bits, bits, memory_order_relaxed);
}

SBAtomicDouble *SBAtomicDoubleCreate(double value) {
    SBAtomicDouble *atomic = malloc(sizeof(*atomic));
    if (atomic) {
        uint64_t bits;
        memcpy(&bits, &value, sizeof(bits));
        atomic_init(&atomic->bits, bits);
    }
    return atomic;
}
void SBAtomicDoubleDestroy(SBAtomicDouble *atomic) { free(atomic); }
double SBAtomicDoubleLoadAcquire(const SBAtomicDouble *atomic) {
    uint64_t bits = atomic_load_explicit(&atomic->bits, memory_order_acquire);
    double value;
    memcpy(&value, &bits, sizeof(value));
    return value;
}
double SBAtomicDoubleLoadRelaxed(const SBAtomicDouble *atomic) {
    uint64_t bits = atomic_load_explicit(&atomic->bits, memory_order_relaxed);
    double value;
    memcpy(&value, &bits, sizeof(value));
    return value;
}
void SBAtomicDoubleStoreRelease(SBAtomicDouble *atomic, double value) {
    uint64_t bits;
    memcpy(&bits, &value, sizeof(bits));
    atomic_store_explicit(&atomic->bits, bits, memory_order_release);
}
void SBAtomicDoubleStoreRelaxed(SBAtomicDouble *atomic, double value) {
    uint64_t bits;
    memcpy(&bits, &value, sizeof(bits));
    atomic_store_explicit(&atomic->bits, bits, memory_order_relaxed);
}

SBAtomicBool *SBAtomicBoolCreate(int value) {
    SBAtomicBool *atomic = malloc(sizeof(*atomic));
    if (atomic) atomic_init(&atomic->value, value != 0);
    return atomic;
}
void SBAtomicBoolDestroy(SBAtomicBool *atomic) { free(atomic); }
int SBAtomicBoolLoadAcquire(const SBAtomicBool *atomic) {
    return atomic_load_explicit(&atomic->value, memory_order_acquire);
}
void SBAtomicBoolStoreRelease(SBAtomicBool *atomic, int value) {
    atomic_store_explicit(&atomic->value, value != 0, memory_order_release);
}

SBAtomicPointer *SBAtomicPointerCreate(uintptr_t value) {
    SBAtomicPointer *atomic = malloc(sizeof(*atomic));
    if (atomic) atomic_init(&atomic->value, value);
    return atomic;
}
void SBAtomicPointerDestroy(SBAtomicPointer *atomic) { free(atomic); }
uintptr_t SBAtomicPointerLoadAcquire(const SBAtomicPointer *atomic) {
    return atomic_load_explicit(&atomic->value, memory_order_acquire);
}
void SBAtomicPointerStoreRelease(SBAtomicPointer *atomic, uintptr_t value) {
    atomic_store_explicit(&atomic->value, value, memory_order_release);
}

SBMessageQueue *SBMessageQueueCreate(size_t capacity) {
    if (capacity < 2) return NULL;
    SBMessageQueue *queue = calloc(1, sizeof(*queue));
    if (!queue) return NULL;
    queue->messages = calloc(capacity, sizeof(SBAtomicMessage));
    if (!queue->messages) {
        free(queue);
        return NULL;
    }
    queue->capacity = capacity;
    atomic_init(&queue->writeIndex, 0);
    atomic_init(&queue->readIndex, 0);
    return queue;
}
void SBMessageQueueDestroy(SBMessageQueue *queue) {
    if (!queue) return;
    free(queue->messages);
    free(queue);
}
int SBMessageQueuePush(SBMessageQueue *queue, SBAtomicMessage message) {
    uint64_t write = atomic_load_explicit(&queue->writeIndex, memory_order_relaxed);
    uint64_t read = atomic_load_explicit(&queue->readIndex, memory_order_acquire);
    if (write - read >= queue->capacity) return 0;
    queue->messages[write % queue->capacity] = message;
    atomic_store_explicit(&queue->writeIndex, write + 1, memory_order_release);
    return 1;
}
int SBMessageQueuePop(SBMessageQueue *queue, SBAtomicMessage *message) {
    uint64_t read = atomic_load_explicit(&queue->readIndex, memory_order_relaxed);
    uint64_t write = atomic_load_explicit(&queue->writeIndex, memory_order_acquire);
    if (read == write) return 0;
    *message = queue->messages[read % queue->capacity];
    atomic_store_explicit(&queue->readIndex, read + 1, memory_order_release);
    return 1;
}
size_t SBMessageQueueCount(const SBMessageQueue *queue) {
    uint64_t write = atomic_load_explicit(&queue->writeIndex, memory_order_acquire);
    uint64_t read = atomic_load_explicit(&queue->readIndex, memory_order_acquire);
    return (size_t)(write - read);
}
