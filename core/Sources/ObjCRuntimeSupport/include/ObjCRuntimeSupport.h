#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

BOOL ObjCMatchesCoordinateGetter(id receiver, SEL selector);
BOOL ObjCMatchesMethodSignature(id receiver, SEL selector, NSString *returnKinds, NSArray<NSString *> *argumentKinds);

id _Nullable ObjCSendId(id receiver, SEL selector);
id _Nullable ObjCAlloc(Class cls);
id _Nullable ObjCSendInitNil(id receiver, SEL selector);
id _Nullable ObjCSendInitId(id receiver, SEL selector, id argument);
id _Nullable ObjCSendInitIdInteger(id receiver, SEL selector, id argument, NSInteger value);
id _Nullable ObjCSendInitIdIdBoolId(id receiver, SEL selector, id first, id second, BOOL flag, id third);
id _Nullable ObjCSendIdBool(id receiver, SEL selector, BOOL value);
id _Nullable ObjCSendIdIdArg(id receiver, SEL selector, id argument);
id _Nullable ObjCSendIdError(id receiver, SEL selector, NSError **error);
id _Nullable ObjCSendIdIdError(id receiver, SEL selector, id argument, NSError **error);
id _Nullable ObjCSendIdIdIdError(id receiver, SEL selector, id first, id second, id third, NSError **error);
id _Nullable ObjCSendIdId(id receiver, SEL selector, id first, id second);
id _Nullable ObjCSendIdIdId(id receiver, SEL selector, id first, id second, id third);
id _Nullable ObjCSendIdIntegerId(id receiver, SEL selector, NSInteger first, id second);
void ObjCSendVoid(id receiver, SEL selector);
void ObjCSendVoidId(id receiver, SEL selector, id argument);
void ObjCSendVoidBool(id receiver, SEL selector, BOOL value);
void ObjCSendVoidInteger(id receiver, SEL selector, NSInteger value);
void ObjCSendVoidInt32(id receiver, SEL selector, int32_t value);
void ObjCSendVoidUInt32(id receiver, SEL selector, uint32_t value);
void ObjCSendVoidDouble(id receiver, SEL selector, double value);
BOOL ObjCSendBool(id receiver, SEL selector);
BOOL ObjCSendBoolError(id receiver, SEL selector, NSError **error);
NSInteger ObjCSendInteger(id receiver, SEL selector);
double ObjCSendDouble(id receiver, SEL selector);
NSArray<NSString *> *ObjCMethodNames(Class cls);
id _Nullable ObjCCallSwiftAllocatingInitializer(
    void *function,
    id firstArgument,
    void *secondArgument,
    id metatype
);

id _Nullable ObjCSafePropertyValue(id receiver, NSString *key, NSError * _Nullable * _Nullable error);

BOOL ObjCRespondsOrForwardsSelector(id receiver, SEL selector);

// Reads a bounded array of three-double native coordinates, validating the full ABI before invocation.
NSArray<NSArray<NSNumber *> *> * _Nullable ObjCReadTripleDoublePoints(id receiver, NSError **error);

NS_ASSUME_NONNULL_END

// Swift resilient value return in x8; class/method self in x20. arm64 only.
uintptr_t ObjCCallSwiftMethodValue(void * _Nonnull function, void * _Nullable swiftSelf, uintptr_t argument0, uintptr_t argument1, void * _Nullable indirectResult);

// A Swift method with self in x20 and four direct argument words in x0-x3 (e.g. an array, an
// object and a closure's function and context). arm64 only.
void ObjCCallSwiftMethod4(void * _Nonnull function, void * _Nullable swiftSelf, uintptr_t argument0, uintptr_t argument1, uintptr_t argument2, uintptr_t argument3);

// Calls a throwing static generic initializer (`init(serializedData:)` style) with a two-word
// consumed argument. Writes Self into result; *errorOut receives the thrown error or NULL. arm64 only.
void ObjCCallSwiftThrowingGenericInit(
    void * _Nonnull function, uintptr_t argument0, uintptr_t argument1, const void * _Nonnull metadata,
    const void * _Nonnull witnessTable, void * _Nonnull result, void * _Nullable * _Nonnull errorOut);
