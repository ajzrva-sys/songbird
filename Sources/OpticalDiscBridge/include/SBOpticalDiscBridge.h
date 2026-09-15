#ifndef SBOpticalDiscBridge_h
#define SBOpticalDiscBridge_h

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SB_OPTICAL_BSD_NAME_MAX 64
#define SB_CDDA_SECTOR_BYTES 2352

typedef struct {
    char bsdName[SB_OPTICAL_BSD_NAME_MAX];
    uint64_t registryID;
} SBOpticalDiscDevice;

typedef struct {
    uint8_t session;
    uint8_t control;
    uint8_t adr;
    uint8_t point;
    int64_t startSector;
} SBOpticalTOCEntry;

int32_t SBOpticalDiscCopyDevices(
    SBOpticalDiscDevice *devices,
    int32_t capacity,
    int32_t *count
);

int32_t SBOpticalDiscReadTOC(
    const char *bsdName,
    SBOpticalTOCEntry *entries,
    int32_t capacity,
    int32_t *count,
    int64_t *leadOutSector
);

int32_t SBOpticalDiscReadCDDASectors(
    const char *bsdName,
    int64_t firstSector,
    int32_t sectorCount,
    uint8_t *buffer,
    int32_t bufferLength,
    int32_t *bytesRead
);

int32_t SBOpticalDiscReadCDText(
    const char *bsdName,
    uint8_t *buffer,
    int32_t capacity,
    int32_t *bytesRead
);

#ifdef __cplusplus
}
#endif

#endif
