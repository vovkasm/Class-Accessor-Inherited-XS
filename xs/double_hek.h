#ifndef __INHERITED_XS_DOUBLE_HEK_H_
#define __INHERITED_XS_DOUBLE_HEK_H_

static const char CAIXS_PKG_PREFIX[] = "__cag_";

struct double_hek {
    U32  hek_hash;
    U32  pkg_hash;
    I32  hek_len;
    char prefix[8]; /* fixed CAIXS_PKG_PREFIX string, shifted by 2 bytes offset to prevent padding */
    char hek_key[1];
};

#define HEK_PKG_LEN(hent) \
    (HEK_LEN(hent) + sizeof(CAIXS_PKG_PREFIX) - 1)

#define HEK_PKG_KEY(hent) \
    ((char*)(hent->prefix) + 2)

#define HEK_PKG_HASH(hent) \
    (hent->pkg_hash)

#define CAIXS_FETCH_PKG_HEK(hv, hent) \
    CAIXS_HASH_FETCH(hv, HEK_PKG_KEY(hent), HEK_PKG_LEN(hent), HEK_PKG_HASH(hent))

#define CAIXS_FETCH_HASH_HEK(hv, hent) \
    CAIXS_HASH_FETCH(hv, HEK_KEY(hent), HEK_LEN(hent), HEK_HASH(hent))

#define CAIXS_HASH_FETCH(hv, key, len, hash) \
    (SV**)hv_common_key_len((hv), (key), (len), HV_FETCH_JUST_SV, NULL, (hash))

#endif