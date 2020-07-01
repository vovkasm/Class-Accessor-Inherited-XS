#ifndef __INHERITED_XS_META_H_
#define __INHERITED_XS_META_H_

extern "C" {
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
}

namespace caixs { namespace meta {

struct FieldMeta {
    SV* name;
    bool required;
    SV* default_value;

    FieldMeta();
    FieldMeta(SV* name_, bool required_, SV* default_value_);
    ~FieldMeta();
    void activate(HV* obj);
};

struct PackageMeta {
    PackageMeta();
    ~PackageMeta();

    void record(SV* hash_key, bool required, SV* default_value);
    void activate(SV* object);
    HV* fields;
};

void init_meta();
void install(SV* full_name, SV* hash_key, bool required, SV* default_value);
void activate(HV* stash, SV* object);

}}

#endif
