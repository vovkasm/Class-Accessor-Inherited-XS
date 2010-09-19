#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#define MY_CXT_KEY "Class::Accessor::Inherited::XS::_guts" XS_VERSION

typedef struct {
    I32 next_ix;
    AV* fields;
} my_cxt_t;

START_MY_CXT

static I32
__poptosub_at(const PERL_CONTEXT *cxstk, I32 startingblock) {
    I32 i;
    for (i = startingblock; i >= 0; i--) {
        if(CxTYPE((PERL_CONTEXT*)(&cxstk[i])) == CXt_SUB) return i;
    }
    return i;
}

XS(CAIXS_inherited_accessor);
XS(CAIXS_inherited_accessor)
{
#ifdef dVAR
    dVAR; dXSARGS;
#else
    dXSARGS;
#endif
    dMY_CXT; dXSI32;

    SV* self = ST(0);

    HE* he;
    HV* stash;
    SV* pkg_acc;
    AV* supers;
    I32 len;
    I32 key;

    SP -= items;

    const GV *const acc_gv = CvGV(cv);
    if (!acc_gv) croak("TODO: can't understand accessor name");

    const char* const c_acc_name = GvNAME(acc_gv);
    SV* const acc = newSVpvn(c_acc_name, strlen(c_acc_name));

    const char* const c_acc_class = HvNAME(GvSTASH(acc_gv));
    SV* const acc_fullname = newSVpvf("%s::%s",c_acc_class,c_acc_name);

    // Determine field name
    SV* *avent = av_fetch( MY_CXT.fields, ix, 0);
    SV* field = (avent == NULL) ? acc : *avent;

    if (sv_isobject(self)) {
        if (SvTYPE(SvRV(self)) != SVt_PVHV)
            croak("Inherited accessor can work only with object instance that is hash-based");

        if (items > 1) {
            SV* newvalue = ST(1);
            if (hv_store_ent( (HV *)SvRV(self), field, newSVsv(newvalue), 0) == NULL)
                croak("Failed to write new value to object instance.");
            PUSHs(newvalue);
            XSRETURN(1);
        }

        if (he = hv_fetch_ent( (HV *)SvRV(self), field, 0, 0)) {
            PUSHs( HeVAL(he) );
            XSRETURN(1);
        }

        stash = SvSTASH(SvRV(self));
    }
    else
        stash = gv_stashsv(self, GV_ADD);

    // Can't find in object, so try self package
    pkg_acc = newSVpvf("__cag_%"SVf,field);

    if (items > 1) {
        SV* newvalue = ST(1);
        SV* fullname = newSVpvf("%s::%"SVf, HvNAME(stash), pkg_acc);
        SV* sv = get_sv(SvPVX(fullname), GV_ADD);
        sv_setsv(sv,newvalue);
        PUSHs( sv );
        XSRETURN(1);
    }

    if (he = hv_fetch_ent( stash, pkg_acc, 0, 0)) {
        SV* sv = GvSV( HeVAL(he) );
        if (sv && SvOK(sv)) {
            PUSHs( sv );
            XSRETURN(1);
        }
    }

    // Now try all superclasses
    supers = mro_get_linear_isa(stash);
    len = av_len(supers);

    for (key = 1; key <= len; key++) {
        SV **svp = av_fetch(supers, key, 0);
        if (svp) {
            SV* super = (SV *)*svp;
            stash = gv_stashsv(super, GV_ADD);

            if (he = hv_fetch_ent( stash, pkg_acc, 0, 0)) {
                SV* sv = GvSV( HeVAL(he) );
                if (sv && SvOK(sv)) {
                    PUSHs( sv );
                    XSRETURN(1);
                }
            }

        }
    }

    XSRETURN_UNDEF;
}

MODULE = Class::Accessor::Inherited::XS		PACKAGE = Class::Accessor::Inherited::XS

BOOT:
{
    MY_CXT_INIT;
    MY_CXT.next_ix = 1;
    MY_CXT.fields = newAV();
}

void
install_inherited_accessor(class,field_name,acc_name)
    SV* class;
    SV* field_name;
    SV* acc_name;
PROTOTYPE: DISABLE
PREINIT:
    dMY_CXT;
INIT:
    SV* acc_fullname = newSVpvf("%"SVf"::%"SVf,class,acc_name);
    CV* cv;
PPCODE:
{
    // Save mapping acc -> field
    if (av_store( MY_CXT.fields, MY_CXT.next_ix, newSVsv(field_name)) == NULL)
        croak("Failed to create mapping '%"SVf"' -> '%"SVf"'.", acc_fullname, field_name);
    // Install XS accessor
    cv = newXS(SvPV_nolen(acc_fullname),CAIXS_inherited_accessor,__FILE__);
    XSANY.any_i32 = MY_CXT.next_ix;

    MY_CXT.next_ix++;

    XSRETURN_UNDEF;
}

