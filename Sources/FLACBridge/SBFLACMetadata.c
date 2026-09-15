#include "SBFLACDecoder.h"
#include <FLAC/metadata.h>
#include <FLAC/format.h>
#include <stdlib.h>
#include <string.h>

int SBFLACWriteTags(
    const char *path,
    const char *const *keys,
    const char *const *values,
    size_t count
) {
    if (!path || count == 0) return -1;
    for (size_t i = 0; i < count; ++i) {
        if (!keys[i] || !values[i]) return -1;
    }

    FLAC__Metadata_Chain *chain = FLAC__metadata_chain_new();
    if (!chain) return -1;
    if (!FLAC__metadata_chain_read(chain, path)) {
        FLAC__metadata_chain_delete(chain);
        return -1;
    }

    FLAC__Metadata_Iterator *iter = FLAC__metadata_iterator_new();
    if (!iter) {
        FLAC__metadata_chain_delete(chain);
        return -1;
    }
    FLAC__metadata_iterator_init(iter, chain);

    int found = 0;
    do {
        if (FLAC__metadata_iterator_get_block_type(iter) ==
            FLAC__METADATA_TYPE_VORBIS_COMMENT) {
            FLAC__StreamMetadata *block = FLAC__metadata_iterator_get_block(iter);
            if (block) {
                for (size_t i = 0; i < count; ++i) {
                    FLAC__StreamMetadata_VorbisComment_Entry entry;
                    if (!FLAC__metadata_object_vorbiscomment_entry_from_name_value_pair(
                            &entry, keys[i], values[i])) {
                        continue;
                    }
                    FLAC__metadata_object_vorbiscomment_replace_comment(
                        block, entry, /*all=*/1, /*copy=*/1);
                }
                found = 1;
            }
            break;
        }
    } while (FLAC__metadata_iterator_next(iter));

    if (!found) {
        FLAC__metadata_iterator_delete(iter);
        FLAC__metadata_chain_delete(chain);
        return -1;
    }

    FLAC__bool ok = FLAC__metadata_chain_write(chain, /*use_padding=*/1, /*preserve_file_stats=*/1);
    FLAC__metadata_iterator_delete(iter);
    FLAC__metadata_chain_delete(chain);
    return ok ? 0 : -1;
}

int SBFLACWriteArtwork(
    const char *path,
    const uint8_t *data,
    size_t data_length,
    const char *mime_type
) {
    if (!path || !data || data_length == 0 || !mime_type) return -1;

    FLAC__Metadata_Chain *chain = FLAC__metadata_chain_new();
    if (!chain) return -1;
    if (!FLAC__metadata_chain_read(chain, path)) {
        FLAC__metadata_chain_delete(chain);
        return -1;
    }

    FLAC__Metadata_Iterator *iter = FLAC__metadata_iterator_new();
    if (!iter) {
        FLAC__metadata_chain_delete(chain);
        return -1;
    }

    /* First pass: look for existing PICTURE block. */
    FLAC__metadata_iterator_init(iter, chain);
    int found = 0;
    for (;;) {
        if (FLAC__metadata_iterator_get_block_type(iter) ==
            FLAC__METADATA_TYPE_PICTURE) {
            FLAC__StreamMetadata *block = FLAC__metadata_iterator_get_block(iter);
            if (block) {
                block->data.picture.type = FLAC__STREAM_METADATA_PICTURE_TYPE_FRONT_COVER;
                block->data.picture.width = 0;
                block->data.picture.height = 0;
                block->data.picture.depth = 0;
                block->data.picture.colors = 0;
                FLAC__metadata_object_picture_set_mime_type(block, (char *)mime_type, 1);
                FLAC__metadata_object_picture_set_data(block, (FLAC__byte *)data, (FLAC__uint32)data_length, 1);
                found = 1;
            }
            break;
        }
        if (!FLAC__metadata_iterator_next(iter)) break;
    }

    if (!found) {
        /* No existing picture block — create one and append. */
        FLAC__StreamMetadata *newBlock = FLAC__metadata_object_new(FLAC__METADATA_TYPE_PICTURE);
        if (!newBlock) {
            FLAC__metadata_iterator_delete(iter);
            FLAC__metadata_chain_delete(chain);
            return -1;
        }
        newBlock->data.picture.type = FLAC__STREAM_METADATA_PICTURE_TYPE_FRONT_COVER;
        FLAC__metadata_object_picture_set_mime_type(newBlock, (char *)mime_type, 1);
        FLAC__metadata_object_picture_set_data(newBlock, (FLAC__byte *)data, (FLAC__uint32)data_length, 1);

        /* Seek to last block. */
        FLAC__metadata_iterator_init(iter, chain);
        while (FLAC__metadata_iterator_next(iter)) {}

        if (!FLAC__metadata_iterator_insert_block_after(iter, newBlock)) {
            FLAC__metadata_object_delete(newBlock);
            FLAC__metadata_iterator_delete(iter);
            FLAC__metadata_chain_delete(chain);
            return -1;
        }
        /* Chain now owns newBlock; freed by FLAC__metadata_chain_delete(). */
    }

    FLAC__bool ok = FLAC__metadata_chain_write(chain, /*use_padding=*/1, /*preserve_file_stats=*/1);
    FLAC__metadata_iterator_delete(iter);
    FLAC__metadata_chain_delete(chain);
    return ok ? 0 : -1;
}
