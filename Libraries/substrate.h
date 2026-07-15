#ifndef SUBSTRATE_H
#define SUBSTRATE_H

#include <objc/runtime.h>

extern void MSHookFunction(void *function, void *hook, void **old);
extern void MSHookMessageEx(Class cls, SEL sel, IMP hook, IMP *old);

#endif
