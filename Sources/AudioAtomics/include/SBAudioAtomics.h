#include <stddef.h>
#include <stdint.h>

typedef struct SBAtomicU64 SBAtomicU64;
typedef struct SBAtomicU32 SBAtomicU32;
typedef struct SBAtomicFloat SBAtomicFloat;
typedef struct SBAtomicDouble SBAtomicDouble;
typedef struct SBAtomicBool SBAtomicBool;
typedef struct SBAtomicPointer SBAtomicPointer;
typedef struct SBMessageQueue SBMessageQueue;

typedef struct {
    uint32_t type;
    uintptr_t pointer;
    uint64_t value;
} SBAtomicMessage;

SBAtomicU64 *SBAtomicU64Create(uint64_t value);
void SBAtomicU64Destroy(SBAtomicU64 *atomic);
uint64_t SBAtomicU64LoadAcquire(const SBAtomicU64 *atomic);
uint64_t SBAtomicU64LoadRelaxed(const SBAtomicU64 *atomic);
void SBAtomicU64StoreRelease(SBAtomicU64 *atomic, uint64_t value);
void SBAtomicU64StoreRelaxed(SBAtomicU64 *atomic, uint64_t value);
uint64_t SBAtomicU64FetchAddRelaxed(SBAtomicU64 *atomic, uint64_t value);
void SBAtomicU64MaxRelaxed(SBAtomicU64 *atomic, uint64_t value);

SBAtomicU32 *SBAtomicU32Create(uint32_t value);
void SBAtomicU32Destroy(SBAtomicU32 *atomic);
uint32_t SBAtomicU32LoadAcquire(const SBAtomicU32 *atomic);
void SBAtomicU32StoreRelease(SBAtomicU32 *atomic, uint32_t value);

SBAtomicFloat *SBAtomicFloatCreate(float value);
void SBAtomicFloatDestroy(SBAtomicFloat *atomic);
float SBAtomicFloatLoadRelaxed(const SBAtomicFloat *atomic);
void SBAtomicFloatStoreRelaxed(SBAtomicFloat *atomic, float value);

SBAtomicDouble *SBAtomicDoubleCreate(double value);
void SBAtomicDoubleDestroy(SBAtomicDouble *atomic);
double SBAtomicDoubleLoadAcquire(const SBAtomicDouble *atomic);
double SBAtomicDoubleLoadRelaxed(const SBAtomicDouble *atomic);
void SBAtomicDoubleStoreRelease(SBAtomicDouble *atomic, double value);
void SBAtomicDoubleStoreRelaxed(SBAtomicDouble *atomic, double value);

SBAtomicBool *SBAtomicBoolCreate(int value);
void SBAtomicBoolDestroy(SBAtomicBool *atomic);
int SBAtomicBoolLoadAcquire(const SBAtomicBool *atomic);
void SBAtomicBoolStoreRelease(SBAtomicBool *atomic, int value);

SBAtomicPointer *SBAtomicPointerCreate(uintptr_t value);
void SBAtomicPointerDestroy(SBAtomicPointer *atomic);
uintptr_t SBAtomicPointerLoadAcquire(const SBAtomicPointer *atomic);
void SBAtomicPointerStoreRelease(SBAtomicPointer *atomic, uintptr_t value);

SBMessageQueue *SBMessageQueueCreate(size_t capacity);
void SBMessageQueueDestroy(SBMessageQueue *queue);
int SBMessageQueuePush(SBMessageQueue *queue, SBAtomicMessage message);
int SBMessageQueuePop(SBMessageQueue *queue, SBAtomicMessage *message);
size_t SBMessageQueueCount(const SBMessageQueue *queue);
