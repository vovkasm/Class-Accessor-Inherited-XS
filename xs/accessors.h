#ifndef __INHERITED_XS_IMPL_H_
#define __INHERITED_XS_IMPL_H_

#include "fimpl.h"
#include "util.h"
#include "op.h"

/*
    These macroses impose the following rules:
        - SP is at the start of the args list
        - SP may become invalid afterwards, so don't touch it
        - PL_stack_sp is updated when needed

    The latter may be not that obvious, but it's a result of a callback doing
    dirty stack work for us. Note that only essential cleanup is done
    after call_sv().
*/

#define CALL_READ_CB(result)                        \
    if (type == InheritedCb && payload->read_cb) {  \
        ENTER;                                      \
        PUSHMARK(SP);                               \
        *(SP+1) = result;                           \
        call_sv(payload->read_cb, G_SCALAR);        \
        LEAVE;                                      \
    } else {                                        \
        *(SP+1) = result;                           \
    }                                               \

#define CALL_WRITE_CB(slot, need_alloc)             \
    if (type == InheritedCb && payload->write_cb) { \
        ENTER;                                      \
        PUSHMARK(SP);                               \
        call_sv(payload->write_cb, G_SCALAR);       \
        SPAGAIN;                                    \
        LEAVE;                                      \
        if (need_alloc) slot = newSV(0);            \
        sv_setsv(slot, *SP);                        \
        *SP = slot;                                 \
    } else {                                        \
        if (need_alloc) slot = newSV(0);            \
        sv_setsv(slot, *(SP+2));                    \
        PUSHs(slot);                                \
        PUTBACK;                                    \
    }                                               \

#define READONLY_TYPE_ASSERT \
    assert(type == Inherited || type == PrivateClass || type == ObjectOnly || type == LazyClass || type == InheritedCompat)

#define READONLY_CROAK_CHECK                            \
    if (type != InheritedCb && is_readonly) {           \
        READONLY_TYPE_ASSERT;                           \
        croak("Can't set value in readonly accessor");  \
        return;                                         \
    }                                                   \

#define SET_GVGP_FLAGS(glob, sv)\
    if (SvOK(sv)) {             \
        GvGPFLAGS_on(glob);     \
                                \
    } else {                    \
        GvGPFLAGS_off(glob);    \
        GvLINE(glob) = 0;       \
    }                           \

static int CAIXS_glob_setter(pTHX_ SV *sv, MAGIC* mg);
static MGVTBL vtcompat = {NULL, CAIXS_glob_setter};

template <bool overflow> static
SV*
CAIXS_icache_get(pTHX_ HV* stash, GV* glob) {
    const struct mro_meta* stash_meta = HvMROMETA(stash);
    const long long curgen = (long long)PL_sub_generation + stash_meta->pkg_gen;

    if (GvLINE(glob) == curgen || GvGPFLAGS(glob)) return GvSV(glob);
    if (overflow && UNLIKELY(curgen > ((U32)1 << 31) - 1)) {
        warn("MRO cache generation 31 bit wraparound");
        PL_sub_generation = 0;
    }

    return NULL;
}

template <bool is_compat> static
SV*
CAIXS_icache_update(pTHX_ HV* stash, GV* glob, SV* pkg_key) {
    AV* supers = mro_get_linear_isa(stash);
    /*
        First entry in the 'mro_get_linear_isa' list is the 'stash' itself.
        It's already been tested, so ajust both counter and iterator to skip over it.
    */
    SSize_t fill     = AvFILLp(supers);
    SV** supers_list = AvARRAY(supers);

    SV* elem;
    SV* result = NULL;

    GV* stack[fill + 1];
#ifdef DEBUGGING
    memzero(stack, (fill + 1) * sizeof(GV*));
#endif
    stack[fill] = glob;

    while (result == NULL && --fill >= 0) {
        elem = *(++supers_list);
        assert(elem); /* mro_get_linear_isa returns dense array */

        HV* next_stash = gv_stashsv(elem, is_compat ? GV_ADD : 0);
        /*
            In non-compat mode, skip entries for empty stashes to save
            some memory. This may result in gaps in the 'stack' array,
            but in this mode we don't care.
        */
        if (is_compat || LIKELY(next_stash != NULL)) {
            GV* next_gv = CAIXS_fetch_glob(aTHX_ next_stash, pkg_key);
            stack[fill] = next_gv;

            result = CAIXS_icache_get<false>(aTHX_ next_stash, next_gv);
        }
    }

    if (UNLIKELY(result == NULL)) {
        assert(fill == -1);

        if (!is_compat) {
            /* this mode doesn't force stash creation in the above loop, so do it here */
            HV* root_stash = gv_stashsv(*supers_list, GV_ADD);
            stack[0] = CAIXS_fetch_glob(aTHX_ root_stash, pkg_key);
        }

        assert(stack[0]);
        result = GvSVn(stack[0]); /* undef from root */
        if (!is_compat) GvGPFLAGS_on(stack[0]); /* yeah, valid 'undef', to speed up lookups later */
    }

    U32 pl_sgen = PL_sub_generation;
    SSize_t new_fill = AvFILLp(supers);

    /*
        For non-compat mode, perfroms a single iteration on the 'glob' variable,
        thus saving memory for non-fetched items. But we can't do that in compat mode,
        as we need magic cast upon everything in between.
    */
    for (int i = (is_compat ? fill + 1 : new_fill); i <= new_fill; ++i) {
        GV* cur_gv = stack[i];
        assert(cur_gv);
        assert(is_compat || cur_gv == glob);

        const struct mro_meta* stash_meta = HvMROMETA(GvSTASH(cur_gv));
        const U32 curgen = pl_sgen + stash_meta->pkg_gen;
        GvLINE(cur_gv) = curgen & (((U32)1 << 31) - 1); /* perl may lack 'gp_flags' field, so we must care about the highest bit */

        if (is_compat) {
            /* copy-by-val + attach watchdog magic */
            SV* sv_slot = GvSVn(cur_gv);
            sv_setsv_nomg(sv_slot, result);

            if (!SvSMAGICAL(sv_slot) || !CAIXS_mg_findext(sv_slot, PERL_MAGIC_ext, &vtcompat)) {
                sv_magicext(sv_slot, (SV*)cur_gv, PERL_MAGIC_ext, &vtcompat, (const char*)pkg_key, HEf_SVKEY);
            }

        } else {
            /* copy-by-reference */
            SV** sv_slot = &GvSV(cur_gv);

            SvREFCNT_inc_simple_void_NN(result);
            SvREFCNT_dec(*sv_slot);
            *sv_slot = result;
        }
    }

    return result;
}

template <bool is_compat> static
void
CAIXS_icache_clear(pTHX_ HV* stash, SV* pkg_key, SV* base_sv) {
    SV** svp = hv_fetchhek(PL_isarev, HvENAME_HEK(stash));
    if (svp) {
        HV* isarev = (HV*)*svp;

        if (HvUSEDKEYS(isarev)) {
            STRLEN hvmax = HvMAX(isarev);
            HE** hvarr = HvARRAY(isarev);

            SV* pl_yes = &PL_sv_yes; /* not that I care much about ithreads, but still */
            for (STRLEN bucket_num = 0; bucket_num <= hvmax; ++bucket_num) {
                for (const HE* he = hvarr[bucket_num]; he; he = HeNEXT(he)) {
                    assert(HeVAL(he) == &PL_sv_placeholder || HeVAL(he) == &PL_sv_yes);

                    if (HeVAL(he) == pl_yes) { /* mro_core.c stores only them */
                        /* access PL_stashcache through HEK interface directly here?  */
                        HEK* hkey = HeKEY_hek(he);
                        HV* revstash = gv_stashpvn(HEK_KEY(hkey), HEK_LEN(hkey), HEK_UTF8(hkey) | GV_ADD);
                        GV* revglob = CAIXS_fetch_glob(aTHX_ revstash, pkg_key);

                        if (is_compat || base_sv == NULL) {
                            assert(!is_compat || base_sv == NULL);

                            /* invalidates all non-root nodes */
                            if (!GvGPFLAGS(revglob)) GvLINE(revglob) = 0;

                        } else {
                            /* since all the cache elements point to the same sv, invalidate only it's copies */
                            if (GvSV(revglob) == base_sv) {
                                assert(!GvGPFLAGS(revglob));
                                GvLINE(revglob) = 0;
                            }
                        }
                    }
                }
            }
        }
    }
}

static int
CAIXS_glob_setter(pTHX_ SV *sv, MAGIC* mg) {
    GV* glob = (GV*)(mg->mg_obj);

    /* InheritedCompat only - cache wipe out */
    SET_GVGP_FLAGS(glob, sv);
    CAIXS_icache_clear<InheritedCompat>(aTHX_ GvSTASH(glob), (SV*)(mg->mg_ptr), NULL);

    return 0;
}

template <bool is_readonly>
struct FImpl<Constructor, is_readonly> {
static void CAIXS_accessor(pTHX_ SV** SP, CV* cv, HV* stash) {
    dAXMARK; dITEMS;

    CAIXS_install_entersub<Constructor, is_readonly>(aTHX);
    if (UNLIKELY(!items)) croak("Usage: $obj->constructor or __PACKAGE__->constructor");

    PL_stack_sp = ++MARK; /* PUTBACK */

    if (!stash) stash = CAIXS_find_stash(aTHX_ *MARK, cv);
    SV** ret = MARK++;

    SV* self;
    if (items == 2 && SvROK(*MARK) && SvTYPE(SvRV(*MARK)) == SVt_PVHV) {
        self = *MARK;

    } else if (items == 2 && !SvOK(*MARK)) {
        self = sv_2mortal(newRV_noinc((SV*)newHV()));

    } else if ((items & 1) == 0) {
        croak("Odd number of elements in hash constructor");

    } else {
        HV* hash = newHV();

        while (MARK < SP) {
            SV* key = *MARK++;
            /* Don't bother with retval here, as in pp_anonhash */
            hv_store_ent(hash, key, newSVsv(*MARK++), 0);
        }

        self = sv_2mortal(newRV_noinc((SV*)hash));
    }

    sv_bless(self, stash);
    *ret = self;
    return;
}};

template <bool is_readonly>
struct FImpl<LazyClass, is_readonly> {
static void CAIXS_accessor(pTHX_ SV** SP, CV* cv, HV* stash) {
    dAXMARK; dITEMS;

    if (UNLIKELY(!items)) croak("Usage: $obj->accessor or __PACKAGE__->accessor");
    shared_keys* payload = CAIXS_find_payload(cv);

    if (items > 1) {
        const int type = LazyClass; /* for READONLY_CROAK_CHECK */
        READONLY_CROAK_CHECK;

        PUSHMARK(SP - items); /* our dAXMARK has popped one */
        FImpl<PrivateClass, is_readonly>::CAIXS_accessor(aTHX_ SP, cv, stash);

    } else {
        ENTER;
        PUSHMARK(--SP); /* SP -= items */
        call_sv(payload->lazy_cb, G_SCALAR);
        SPAGAIN;
        LEAVE;

        sv_setsv(payload->storage, *SP);
        *SP = payload->storage;
    }

    CvXSUB(cv) = (XSUBADDR_t)&CAIXS_entersub_wrapper<PrivateClass, is_readonly>;
    SvREFCNT_dec_NN(payload->lazy_cb);
    payload->lazy_cb = NULL;

    return;
}};

template <bool is_readonly>
struct FImpl<PrivateClass, is_readonly> {
static void CAIXS_accessor(pTHX_ SV** SP, CV* cv, HV* stash) {
    dAXMARK; dITEMS;
    SP -= items;

    if (UNLIKELY(!items)) croak("Usage: $obj->accessor or __PACKAGE__->accessor");

    CAIXS_install_entersub<PrivateClass, is_readonly>(aTHX);
    shared_keys* payload = CAIXS_find_payload(cv);

    const int type = PrivateClass; /* for CALL_*_CB */

    if (items == 1) {
        CALL_READ_CB(payload->storage);
        return;
    }

    READONLY_CROAK_CHECK;
    CALL_WRITE_CB(payload->storage, 0);
    return;
}};

/* covers type = {Inherited, InheritedCb, InheritedCompat, ObjectOnly} */
template <AccessorType type, bool is_readonly>
struct FImpl {
static void CAIXS_accessor(pTHX_ SV** SP, CV* cv, HV* stash) {
    dAXMARK; dITEMS;
    SP -= items;

    if (UNLIKELY(!items)) croak("Usage: $obj->accessor or __PACKAGE__->accessor");

    CAIXS_install_entersub<type, is_readonly>(aTHX);
    shared_keys* payload = CAIXS_find_payload(cv);

    SV* self = *(SP+1);
    if (SvROK(self)) {
        HV* obj = (HV*)SvRV(self);
        if (UNLIKELY(SvTYPE((SV*)obj) != SVt_PVHV)) {
            croak("Inherited accessors work only with hash-based objects");
        }

        if (items > 1) {
            READONLY_CROAK_CHECK;

            SV* new_value;
            CALL_WRITE_CB(new_value, 1);
            if (UNLIKELY(!hv_store_ent(obj, payload->hash_key, new_value, 0))) {
                SvREFCNT_dec_NN(new_value);
                croak("Can't store new hash value");
            }
            return;
                    
        } else {
            HE* hent = hv_fetch_ent(obj, payload->hash_key, 0, 0);
            if (hent) {
                CALL_READ_CB(HeVAL(hent));
                return;

            } else if (type == ObjectOnly) {
                CALL_READ_CB(&PL_sv_undef);
                return;
            }
        }
    }

    if (type == ObjectOnly) {
        croak("Can't use object accessor on non-object");
        return; /* gcc detects unreachability even with bare croak(), but it won't hurt */
    }

    /* Couldn't find value in the object, so initiate a package lookup. */

    if (!stash) stash = CAIXS_find_stash(aTHX_ self, cv);

    if (items > 1) {
        READONLY_CROAK_CHECK;

        GV* glob = CAIXS_fetch_glob(aTHX_ stash, payload->pkg_key);
        SV* new_value = GvSV(glob);

        if (type == InheritedCompat) {
            if (UNLIKELY(new_value == NULL)) {
                GvSV(glob) = newSV(0);
                new_value = GvSV(glob);
            }

            if (!SvSMAGICAL(new_value) || !CAIXS_mg_findext(new_value, PERL_MAGIC_ext, &vtcompat)) {
                sv_magicext(new_value, (SV*)glob, PERL_MAGIC_ext, &vtcompat, (const char*)(payload->pkg_key), HEf_SVKEY);
            }

            /* Wipe the whole cache from down there */
            CAIXS_icache_clear<true>(aTHX_ stash, payload->pkg_key, NULL);

        } else {
            if (!GvGPFLAGS(glob)) {
                /*
                    When this is an already calculated cache point (new_value != NULL),
                    wipe will be performed only to the 'new_value' copies. Otherwise,
                    like in the above case, the whole cache gets erased.
                */
                CAIXS_icache_clear<false>(aTHX_ stash, payload->pkg_key, new_value);
                SvREFCNT_dec(new_value);

                GvSV(glob) = newSV(0);
                new_value = GvSV(glob);

            } else {
                assert(new_value);
            }
        }

        CALL_WRITE_CB(new_value, 0);
        SET_GVGP_FLAGS(glob, new_value);

        return;
    }

    GV* glob = CAIXS_fetch_glob(aTHX_ stash, payload->pkg_key);
    SV* result = CAIXS_icache_get<true>(aTHX_ stash, glob);

    /* lazy cache builder */
    if (!result) result = CAIXS_icache_update<type == InheritedCompat>(aTHX_ stash, glob, payload->pkg_key);

    CALL_READ_CB(result);
    return;
}};

#endif /* __INHERITED_XS_IMPL_H_ */
