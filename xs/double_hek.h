#ifndef __INHERITED_XS_DOUBLE_HEK_H_
#define __INHERITED_XS_DOUBLE_HEK_H_

static const char CAIXS_PKG_PREFIX[] = "__cag_";

typedef struct double_hek {
    U32  hek_hash;
    U32  pkg_hash;
    I32  hek_len;
    char buffer[4]; /* CAIXS_PKG_PREFIX, key, zero byte, flags */
} double_hek;

#define DHEK_HASH(hent) \
    (hent->hek_hash)

#define DHEK_PKG_HASH(hent) \
    (hent->pkg_hash)

#define DHEK_LEN(hent) \
    (hent->hek_len)

#define DHEK_PKG_LEN(hent) \
    (HEK_LEN(hent) + sizeof(CAIXS_PKG_PREFIX) - 1)

#define DHEK_KEY(hent) \
    ((char*)(hent->buffer) + 6)

#define DHEK_PKG_KEY(hent) \
    (hent->buffer)

#define DHEK_FLAGS(hent) \
    (*((unsigned char *)(DHEK_KEY(hent))+DHEK_LEN(hent)+1))

#define DHEK_UTF8(hent) \
    (DHEK_FLAGS(hent) & HVhek_UTF8)

#define CAIXS_FETCH_PKG_HEK(hv, hent) \
    CAIXS_HASH_FETCH(hv, DHEK_PKG_KEY(hent), DHEK_PKG_LEN(hent), DHEK_PKG_HASH(hent), DHEK_UTF8(hent))

#define CAIXS_FETCH_HASH_HEK(hv, hent) \
    CAIXS_HASH_FETCH(hv, DHEK_KEY(hent), DHEK_LEN(hent), DHEK_HASH(hent), DHEK_UTF8(hent))

#define CAIXS_HASH_FETCH(hv, key, len, hash, flags) \
    (SV**)hv_common((hv), NULL, (key), (len), (flags), HV_FETCH_JUST_SV, NULL, (hash))

#endif
