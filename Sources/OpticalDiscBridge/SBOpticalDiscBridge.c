#include "SBOpticalDiscBridge.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/storage/IOCDMedia.h>
#include <IOKit/storage/IOCDMediaBSDClient.h>
#include <IOKit/storage/IOMedia.h>
#include <fcntl.h>
#include <libkern/OSByteOrder.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

static int sb_open_raw_device(const char *bsdName) {
    if (bsdName == NULL || bsdName[0] == '\0') return -1;
    char path[128] = {0};
    if (snprintf(path, sizeof(path), "/dev/r%s", bsdName) >= (int)sizeof(path)) return -1;
    return open(path, O_RDONLY | O_NONBLOCK);
}

int32_t SBOpticalDiscCopyDevices(
    SBOpticalDiscDevice *devices,
    int32_t capacity,
    int32_t *count
) {
    if (count == NULL || capacity < 0) return EINVAL;
    *count = 0;
    io_iterator_t iterator = IO_OBJECT_NULL;
    kern_return_t result = IOServiceGetMatchingServices(
        kIOMainPortDefault,
        IOServiceMatching(kIOCDMediaClass),
        &iterator
    );
    if (result != KERN_SUCCESS) return result;

    io_service_t service;
    while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        CFTypeRef whole = IORegistryEntryCreateCFProperty(
            service,
            CFSTR(kIOMediaWholeKey),
            kCFAllocatorDefault,
            0
        );
        bool isWhole = whole != NULL && CFGetTypeID(whole) == CFBooleanGetTypeID()
            && CFBooleanGetValue((CFBooleanRef)whole);
        if (whole != NULL) CFRelease(whole);
        if (!isWhole) {
            IOObjectRelease(service);
            continue;
        }
        CFTypeRef value = IORegistryEntryCreateCFProperty(
            service,
            CFSTR(kIOBSDNameKey),
            kCFAllocatorDefault,
            0
        );
        if (value != NULL && CFGetTypeID(value) == CFStringGetTypeID()) {
            int32_t index = *count;
            if (devices != NULL && index < capacity) {
                memset(&devices[index], 0, sizeof(devices[index]));
                CFStringGetCString(
                    (CFStringRef)value,
                    devices[index].bsdName,
                    sizeof(devices[index].bsdName),
                    kCFStringEncodingUTF8
                );
                IORegistryEntryGetRegistryEntryID(service, &devices[index].registryID);
            }
            *count = index + 1;
        }
        if (value != NULL) CFRelease(value);
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    return 0;
}

int32_t SBOpticalDiscReadTOC(
    const char *bsdName,
    SBOpticalTOCEntry *entries,
    int32_t capacity,
    int32_t *count,
    int64_t *leadOutSector
) {
    if (count == NULL || leadOutSector == NULL || capacity < 0) return EINVAL;
    *count = 0;
    *leadOutSector = 0;
    int fd = sb_open_raw_device(bsdName);
    if (fd < 0) return errno;

    uint8_t tocBuffer[4096] = {0};
    dk_cd_read_toc_t request = {0};
    request.format = kCDTOCFormatTOC;
    request.formatAsTime = 0;
    request.bufferLength = sizeof(tocBuffer);
    request.buffer = tocBuffer;
    int status = ioctl(fd, DKIOCCDREADTOC, &request);
    int savedErrno = errno;
    close(fd);
    if (status != 0) return savedErrno;

    CDTOC *toc = (CDTOC *)tocBuffer;
    uint32_t descriptorCount = CDTOCGetDescriptorCount(toc);
    for (uint32_t index = 0; index < descriptorCount; index++) {
        CDTOCDescriptor descriptor = toc->descriptors[index];
        if (descriptor.adr != 1) continue;
        int64_t sector = (int64_t)CDConvertMSFToClippedLBA(descriptor.p);
        if (descriptor.point == 0xA2) {
            *leadOutSector = sector;
            continue;
        }
        if (descriptor.point < 1 || descriptor.point > 99) continue;
        int32_t outputIndex = *count;
        if (entries != NULL && outputIndex < capacity) {
            entries[outputIndex] = (SBOpticalTOCEntry) {
                .session = descriptor.session,
                .control = descriptor.control,
                .adr = descriptor.adr,
                .point = descriptor.point,
                .startSector = sector,
            };
        }
        *count = outputIndex + 1;
    }
    return 0;
}

int32_t SBOpticalDiscReadCDDASectors(
    const char *bsdName,
    int64_t firstSector,
    int32_t sectorCount,
    uint8_t *buffer,
    int32_t bufferLength,
    int32_t *bytesRead
) {
    if (buffer == NULL || bytesRead == NULL || firstSector < 0 || sectorCount <= 0) return EINVAL;
    int64_t expected = (int64_t)sectorCount * SB_CDDA_SECTOR_BYTES;
    if (expected > bufferLength || expected > UINT32_MAX) return ENOBUFS;
    *bytesRead = 0;
    int fd = sb_open_raw_device(bsdName);
    if (fd < 0) return errno;
    dk_cd_read_t request = {0};
    request.offset = (uint64_t)firstSector * SB_CDDA_SECTOR_BYTES;
    request.sectorArea = kCDSectorAreaUser;
    request.sectorType = kCDSectorTypeCDDA;
    request.bufferLength = (uint32_t)expected;
    request.buffer = buffer;
    int status = ioctl(fd, DKIOCCDREAD, &request);
    int savedErrno = errno;
    close(fd);
    if (status != 0) return savedErrno;
    *bytesRead = (int32_t)request.bufferLength;
    return 0;
}

int32_t SBOpticalDiscReadCDText(
    const char *bsdName,
    uint8_t *buffer,
    int32_t capacity,
    int32_t *bytesRead
) {
    if (buffer == NULL || bytesRead == NULL || capacity <= 0 || capacity > UINT16_MAX) return EINVAL;
    *bytesRead = 0;
    int fd = sb_open_raw_device(bsdName);
    if (fd < 0) return errno;
    dk_cd_read_toc_t request = {0};
    request.format = kCDTOCFormatTEXT;
    request.formatAsTime = 0;
    request.bufferLength = (uint16_t)capacity;
    request.buffer = buffer;
    int status = ioctl(fd, DKIOCCDREADTOC, &request);
    int savedErrno = errno;
    close(fd);
    if (status != 0) return savedErrno;
    *bytesRead = request.bufferLength;
    return 0;
}
