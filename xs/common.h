#ifndef __INHERITED_XS_COMMON_H_
#define __INHERITED_XS_COMMON_H_

extern "C" {
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
}

inline MAGIC*
CAIXS_mg_findext(SV* sv, int type, MGVTBL* vtbl) {
    MAGIC* mg;

    if (sv) {
        for (mg = SvMAGIC(sv); mg; mg = mg->mg_moremagic) {
            if (mg->mg_type == type && mg->mg_virtual == vtbl) {
                return mg;
            }
        }
    }

    return NULL;
}

#endif
