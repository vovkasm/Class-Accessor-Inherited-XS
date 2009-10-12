#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"


MODULE = Class::Accessor::Inherited::XS		PACKAGE = Class::Accessor::Inherited::XS

void
get_inherited(self,acc)
    SV* self;
    SV* acc;
PROTOTYPE: DISABLE
INIT:
    HE* he;
    HV* stash;
    SV* pkg_acc;
    AV* supers;
    I32 len;
    I32 key;
PPCODE:
{
    if (sv_isobject(self)) {
        if (SvTYPE(SvRV(self)) != SVt_PVHV)
            croak("Cannot get inherited value on an object instance that is not hash-based");

        if (he = hv_fetch_ent( (HV *)SvRV(self), acc, 0, 0)) {
            PUSHs( HeVAL(he) );
            XSRETURN(1);
        }

        stash = SvSTASH(SvRV(self));
    }
    else
        stash = gv_stashsv(self, GV_ADD);

    // Can't find in object, so try self package
    pkg_acc = newSVpvn("__cag_",6);
    sv_catsv(pkg_acc, acc);

    /*    

    if (he = hv_fetch_ent( stash, pkg_acc, 0, 0)) {
        PUSHs( HeVAL(he) );
        XSRETURN(1);
    }
    */
    // Now try all superclasses
    supers = mro_get_linear_isa(stash);
    len = av_len(supers);

    for (key = 0; key <= len; key++) {
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
