#import "ObjCRuntimeSupport.h"
#import <objc/message.h>
#import <objc/runtime.h>

id ObjCSendId(id receiver, SEL selector) {
    return ((id (*)(id, SEL))objc_msgSend)(receiver, selector);
}

id ObjCAlloc(Class cls) {
    return ((id (*)(Class, SEL))objc_msgSend)(cls, sel_registerName("alloc"));
}

id ObjCSendInitNil(id receiver, SEL selector) {
    return ((id (*)(id, SEL, id))objc_msgSend)(receiver, selector, nil);
}

id ObjCSendInitId(id receiver, SEL selector, id argument) {
    return ((id (*)(id, SEL, id))objc_msgSend)(receiver, selector, argument);
}

id ObjCSendInitIdInteger(id receiver, SEL selector, id argument, NSInteger value) {
    return ((id (*)(id, SEL, id, NSInteger))objc_msgSend)(receiver, selector, argument, value);
}

id ObjCSendInitIdIdBoolId(id receiver, SEL selector, id first, id second, BOOL flag, id third) {
    return ((id (*)(id, SEL, id, id, BOOL, id))objc_msgSend)(receiver, selector, first, second, flag, third);
}

id ObjCSendIdBool(id receiver, SEL selector, BOOL value) {
    return ((id (*)(id, SEL, BOOL))objc_msgSend)(receiver, selector, value);
}

id ObjCSendIdIdArg(id receiver, SEL selector, id argument) {
    return ((id (*)(id, SEL, id))objc_msgSend)(receiver, selector, argument);
}

id ObjCSendIdError(id receiver, SEL selector, NSError **error) {
    return ((id (*)(id, SEL, NSError **))objc_msgSend)(receiver, selector, error);
}

id ObjCSendIdIdError(id receiver, SEL selector, id argument, NSError **error) {
    return ((id (*)(id, SEL, id, NSError **))objc_msgSend)(receiver, selector, argument, error);
}

id ObjCSendIdIdIdError(id receiver, SEL selector, id first, id second, id third, NSError **error) {
    return ((id (*)(id, SEL, id, id, id, NSError **))objc_msgSend)(receiver, selector, first, second, third, error);
}

id ObjCSendIdId(id receiver, SEL selector, id first, id second) {
    return ((id (*)(id, SEL, id, id))objc_msgSend)(receiver, selector, first, second);
}

id ObjCSendIdIdId(id receiver, SEL selector, id first, id second, id third) {
    return ((id (*)(id, SEL, id, id, id))objc_msgSend)(receiver, selector, first, second, third);
}

id ObjCSendIdIntegerId(id receiver, SEL selector, NSInteger first, id second) {
    return ((id (*)(id, SEL, NSInteger, id))objc_msgSend)(receiver, selector, first, second);
}

void ObjCSendVoid(id receiver, SEL selector) {
    ((void (*)(id, SEL))objc_msgSend)(receiver, selector);
}

void ObjCSendVoidId(id receiver, SEL selector, id argument) {
    ((void (*)(id, SEL, id))objc_msgSend)(receiver, selector, argument);
}

void ObjCSendVoidBool(id receiver, SEL selector, BOOL value) {
    ((void (*)(id, SEL, BOOL))objc_msgSend)(receiver, selector, value);
}

void ObjCSendVoidInteger(id receiver, SEL selector, NSInteger value) {
    ((void (*)(id, SEL, NSInteger))objc_msgSend)(receiver, selector, value);
}

void ObjCSendVoidDouble(id receiver, SEL selector, double value) {
    ((void (*)(id, SEL, double))objc_msgSend)(receiver, selector, value);
}

BOOL ObjCSendBool(id receiver, SEL selector) {
    return ((BOOL (*)(id, SEL))objc_msgSend)(receiver, selector);
}

BOOL ObjCSendBoolError(id receiver, SEL selector, NSError **error) {
    return ((BOOL (*)(id, SEL, NSError **))objc_msgSend)(receiver, selector, error);
}

NSInteger ObjCSendInteger(id receiver, SEL selector) {
    return ((NSInteger (*)(id, SEL))objc_msgSend)(receiver, selector);
}

double ObjCSendDouble(id receiver, SEL selector) {
    return ((double (*)(id, SEL))objc_msgSend)(receiver, selector);
}

NSArray<NSString *> *ObjCMethodNames(Class cls) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];

    Class current = cls;
    while (current) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(current, &count);
        for (unsigned int index = 0; index < count; index++) {
            SEL selector = method_getName(methods[index]);
            [names addObject:NSStringFromSelector(selector)];
        }
        free(methods);
        current = class_getSuperclass(current);
    }

    return [names sortedArrayUsingSelector:@selector(compare:)];
}

id ObjCSafePropertyValue(id receiver, NSString *key, NSError **error) {
    if (![receiver respondsToSelector:NSSelectorFromString(key)]) { return nil; }
    @try {
        return [receiver valueForKey:key];
    } @catch (NSException *exception) {
        if (error) {
            *error = [NSError errorWithDomain:@"Gesher.NativeProperty" code:1
                                    userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: exception.name}];
        }
        return nil;
    }
}

BOOL ObjCRespondsOrForwardsSelector(id receiver, SEL selector) {
    if ([receiver respondsToSelector:selector]) { return YES; }
    @try {
        // CADXPCProxyHelper forwards protocol methods without advertising respondsToSelector.
        return [receiver methodSignatureForSelector:selector] != nil;
    } @catch (NSException *exception) {
        return NO;
    }
}

static BOOL ObjCTypeMatches(const char *type, NSString *kinds) {
    while (*type && strchr("rnNoORV", *type)) type++;
    if (!*type) return NO;
    return [kinds rangeOfString:[NSString stringWithFormat:@"%c", *type]].location != NSNotFound;
}

BOOL ObjCMatchesMethodSignature(id receiver, SEL selector, NSString *returnKinds, NSArray<NSString *> *argumentKinds) {
    @try {
        NSMethodSignature *signature = [receiver methodSignatureForSelector:selector];
        if (!signature || signature.numberOfArguments != argumentKinds.count + 2 ||
            !ObjCTypeMatches(signature.methodReturnType, returnKinds)) return NO;
        for (NSUInteger index = 0; index < argumentKinds.count; index++) {
            if (!ObjCTypeMatches([signature getArgumentTypeAtIndex:index + 2], argumentKinds[index])) return NO;
        }
        return YES;
    } @catch (NSException *exception) { return NO; }
}

void ObjCSendVoidInt32(id receiver, SEL selector, int32_t value) {
    ((void (*)(id, SEL, int32_t))objc_msgSend)(receiver, selector, value);
}
void ObjCSendVoidUInt32(id receiver, SEL selector, uint32_t value) {
    ((void (*)(id, SEL, uint32_t))objc_msgSend)(receiver, selector, value);
}

BOOL ObjCMatchesCoordinateGetter(id receiver, SEL selector) {
    @try {
        NSMethodSignature *signature = [receiver methodSignatureForSelector:selector];
        if (!signature || signature.numberOfArguments != 2 || signature.methodReturnLength != 2 * sizeof(double)) return NO;
        const char *encoding = signature.methodReturnType;
        const char *fields = strchr(encoding, '=');
        return encoding[0] == '{' && fields && strcmp(fields, "=dd}") == 0;
    } @catch (NSException *exception) { return NO; }
}

NSArray<NSArray<NSNumber *> *> *ObjCReadTripleDoublePoints(id receiver, NSError **error) {
    @try {
        SEL countSelector = NSSelectorFromString(@"pointCount");
        SEL pointSelector = NSSelectorFromString(@"pointAt:");
        NSMethodSignature *countSignature = [receiver methodSignatureForSelector:countSelector];
        NSMethodSignature *pointSignature = [receiver methodSignatureForSelector:pointSelector];
        const char *fields = pointSignature ? strchr(pointSignature.methodReturnType, '=') : NULL;
        if (!countSignature || countSignature.numberOfArguments != 2 ||
            strcmp(countSignature.methodReturnType, "I") ||
            !pointSignature || pointSignature.numberOfArguments != 3 ||
            pointSignature.methodReturnType[0] != '{' || !fields || strcmp(fields, "=ddd}") ||
            pointSignature.methodReturnLength != 3 * sizeof(double) ||
            strcmp([pointSignature getArgumentTypeAtIndex:2], @encode(NSUInteger))) {
            if (error) *error = [NSError errorWithDomain:@"Gesher.NativeGeometry" code:1
                userInfo:@{NSLocalizedDescriptionKey: @"Native coordinate ABI is unavailable."}];
            return nil;
        }
        uint32_t count = ((uint32_t (*)(id, SEL))objc_msgSend)(receiver, countSelector);
        if (count > 200000) {
            if (error) *error = [NSError errorWithDomain:@"Gesher.NativeGeometry" code:2
                userInfo:@{NSLocalizedDescriptionKey: @"Native coordinate count exceeds the safety limit."}];
            return nil;
        }
        typedef struct { double latitude, longitude, elevation; } ObjCTriplePoint;
        NSMutableArray *points = [NSMutableArray arrayWithCapacity:count];
        for (NSUInteger i = 0; i < count; i++) {
            ObjCTriplePoint point = ((ObjCTriplePoint (*)(id, SEL, NSUInteger))objc_msgSend)(receiver, pointSelector, i);
            [points addObject:@[@(point.latitude), @(point.longitude)]];
        }
        return points;
    } @catch (NSException *exception) {
        if (error) *error = [NSError errorWithDomain:@"Gesher.NativeGeometry" code:3
            userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: exception.name}];
        return nil;
    }
}
