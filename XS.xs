#define PERL_NO_GET_CONTEXT

#include <xs/xs.h>
using namespace xs;

static const char CAIXS_PKG_PREFIX[] = "__cag_";

#define HEK_PKG_LEN(hent) \
    (HEK_LEN(hent) + sizeof(CAIXS_PKG_PREFIX) - 1)

#define HEK_PKG_KEY(hent) \
    (hent->prefix)

#define HEK_PKG_HASH(hent) \
    (hent->pkg_hash)

struct double_hek {
    U32  hek_hash;
    U32  pkg_hash;
    I32  hek_len;
    char prefix[sizeof(CAIXS_PKG_PREFIX) - 1]; /* fixed CAIXS_PKG_PREFIX string */
    char hek_key[1]; 
};

#define CAIXS_FETCH_PKG_HEK(hv, hent) \
    CAIXS_HASH_FETCH(hv, HEK_PKG_KEY(hent), HEK_PKG_LEN(hent), HEK_PKG_HASH(hent))

#define CAIXS_FETCH_HASH_HEK(hv, hent) \
    CAIXS_HASH_FETCH(hv, HEK_KEY(hent), HEK_LEN(hent), HEK_HASH(hent))

#define CAIXS_HASH_FETCH(hv, key, len, hash) \
    (SV**)hv_common_key_len((hv), (key), (len), HV_FETCH_JUST_SV, NULL, (hash))

#define CREATE_KEY_SV(var, key)                                                     \
STMT_START {                                                                        \
    STRLEN len;                                                                     \
    const char* buf = SvPV(key, len);                                               \
    var = newSV(sizeof(double_hek) + len);                                          \
    double_hek* hent = (double_hek*)SvPVX(var);                                     \
    HEK_LEN(hent) = len;                                                            \
    memcpy(HEK_PKG_KEY(hent), CAIXS_PKG_PREFIX, sizeof(CAIXS_PKG_PREFIX) - 1);      \
    memcpy(HEK_KEY(hent), buf, len + 1);                                            \
    PERL_HASH(HEK_HASH(hent), buf, len);                                            \
    len += sizeof(CAIXS_PKG_PREFIX) - 1;                                            \
    PERL_HASH(HEK_PKG_HASH(hent), HEK_PKG_KEY(hent), len);                          \
    /*HEK_FLAGS(hent) = 0;*/                                                        \
} STMT_END

static payload_marker_t* my_marker = sv_payload_marker("Class::Accessor::Inherited::XS");

XS(CAIXS_inherited_accessor);

static void
CAIXS_install_accessor(pTHX_ const char* full_name, SV* hash_key)
{
    CV* cv = newXS(full_name, CAIXS_inherited_accessor, __FILE__);
    SV* keysv;
    CREATE_KEY_SV(keysv, hash_key);
    sv_payload_attach((SV*)cv, keysv, my_marker);
    SvREFCNT_dec_NN(keysv); 
    CvXSUBANY(cv).any_ptr = (void*)keysv;
}

XS(CAIXS_inherited_accessor)
{
    dVAR; dXSARGS;
    dXSI32;
    
    SP -= items;
    
    SV* self = ST(0);

    SV* keysv = (SV*)(CvXSUBANY(cv).any_ptr);
    //SV* keysv = sv_payload_sv((SV*)cv, my_marker);
    if (!keysv) croak("Can't find hash key information");

    double_hek* hent = (double_hek*)SvPVX(keysv);

    if (SvROK(self)) {
        HV* obj = (HV*)SvRV(self);
        if (SvTYPE((SV*)obj) != SVt_PVHV)
            croak("Inherited accessor can work only with object instance that is hash-based");

        if (items > 1) {
            SV* orig_value = ST(1);
            SV* new_value  = newSVsv(orig_value);
            if (!hv_store((HV*)SvRV(self), HEK_KEY(hent), HEK_LEN(hent), new_value, HEK_HASH(hent))) {
                croak("Can't store new hash value");
            }
            PUSHs(new_value);
            XSRETURN(1);
                    
        } else {
            SV** svp = CAIXS_FETCH_HASH_HEK(obj, hent);
            if (svp) {
                PUSHs(*svp);
                XSRETURN(1);
            }
        }
    }

    I32 key;

    // Can't find in object, so try self package

    static char fullname[256];
    STRLEN len;
    const char* pkg_name = SvPV(self, len);
    snprintf(fullname, 255, "%s::__cag_%s", pkg_name, HEK_KEY(hent));

    if (items > 1) {
        SV* orig_value = ST(1);

        //SV* fullname = newSVpvf("%s::%s", SvPV_nolen(self), );
        //SV* acc_fullname = newSVpvf("%s::%"SVf, HvNAME(stash), acc);
        //CAIXS_install_accessor(aTHX_ c_acc_name, c_acc_name);

        SV* new_value = get_sv(fullname, GV_ADD);
        sv_setsv(new_value, orig_value);
        PUSHs(new_value);

        XSRETURN(1);
    }
    
    GV* acc_gv = CvGV(cv);
    if (!acc_gv) croak("TODO: can't understand accessor name");

    HV* stash;
    if (SvROK(self)) {
        stash = SvSTASH(SvRV(self));
    } else {
        stash = gv_stashsv(self, 0);
        //stash = GvSTASH(acc_gv);
    }
    
    SV** svp;
    if (stash && (svp = CAIXS_FETCH_PKG_HEK(stash, hent))) {
        SV* sv = GvSV(*svp);
        if (sv && SvOK(sv)) {
            PUSHs(sv);
            XSRETURN(1);
        }
    }

    // Now try all superclasses
    AV* supers = mro_get_linear_isa(stash);
    len = av_len(supers);

    HE* he;
    for (key = 1; key <= len; key++) {
        svp = av_fetch(supers, key, 0);
        if (svp) {
            SV* super = (SV *)*svp;
            stash = gv_stashsv(super, 0);

            if (stash && (svp = CAIXS_FETCH_PKG_HEK(stash, hent))) {
                SV* sv = GvSV(*svp);
                if (sv && SvOK(sv)) {
                    PUSHs(sv);
                    XSRETURN(1);
                }
            }
        }
    }

    XSRETURN_UNDEF;
}

MODULE = Class::Accessor::Inherited::XS		PACKAGE = Class::Accessor::Inherited::XS
PROTOTYPES: DISABLE

void install_inherited_accessor(const char* full_name, SV* hash_key) {
    CAIXS_install_accessor(aTHX_ full_name, hash_key);
    XSRETURN_UNDEF;
}

