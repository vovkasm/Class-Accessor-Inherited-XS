#ifndef __INHERITED_XS_META_H_
#define __INHERITED_XS_META_H_

extern "C" {
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
}

namespace caixs { namespace meta {

typedef AV* PackageMeta;

void install(CV* cv, SV* hash_key, SV *required, SV* default_value);
void activate(HV* stash, SV* object);

}}

#endif
