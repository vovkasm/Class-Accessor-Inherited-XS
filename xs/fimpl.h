#ifndef __INHERITED_XS_FIMPL_H_
#define __INHERITED_XS_FIMPL_H_

template <AccessorType type, bool is_readonly>
struct FImpl;

template <AccessorType type, bool is_readonly> inline
void
CAIXS_accessor(pTHX_ SV** SP, CV* cv, HV* stash) {
    FImpl<type, is_readonly>::CAIXS_accessor(aTHX_ SP, cv, stash);
}

#endif /* __INHERITED_XS_FIMPL_H_ */
