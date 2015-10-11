// RUN: %target-swift-frontend -emit-sil -disable-objc-attr-requires-foundation-module %s | FileCheck %s

// High-level tests that DI accepts and rejects failure from failable
// initializers properly.

// For value types, we can handle failure at any point, using DI's established
// analysis for partial struct and tuple values.

// FIXME: not all of the test cases have CHECKs. Hopefully the interesting cases
// are fully covered, though.

////
// Structs with failable initializers
////

protocol Pachyderm {
  init()
}

class Canary : Pachyderm {
  required init() {}
}

// <rdar://problem/20941576> SILGen crash: Failable struct init cannot delegate to another failable initializer
struct TrivialFailableStruct {
  init?(blah: ()) { }
  init?(wibble: ()) {
    self.init(blah: wibble)
  }
}

struct FailableStruct {
  let x, y: Canary

  init(noFail: ()) {
    x = Canary()
    y = Canary()
  }

// CHECK-LABEL: sil hidden @_TFV35definite_init_failable_initializers14FailableStructCfMS0_FT24failBeforeInitializationT__GSqS0__
// CHECK:       bb0(%0 : $@thin FailableStruct.Type):
// CHECK:         [[SELF_BOX:%.*]] = alloc_stack $FailableStruct
// CHECK:         br bb1
// CHECK:       bb1:
// CHECK-NEXT:    [[SELF:%.*]] = enum $Optional<FailableStruct>, #Optional.None!enumelt
// CHECK-NEXT:    br bb2
// CHECK:       bb2:
// CHECK-NEXT:    dealloc_stack [[SELF_BOX]]#0
// CHECK-NEXT:    return [[SELF]]
  init?(failBeforeInitialization: ()) {
    return nil
  }

// CHECK-LABEL: sil hidden @_TFV35definite_init_failable_initializers14FailableStructCfMS0_FT30failAfterPartialInitializationT__GSqS0__
// CHECK:       bb0(%0 : $@thin FailableStruct.Type):
// CHECK:         [[SELF_BOX:%.*]] = alloc_stack $FailableStruct
// CHECK:         [[CANARY:%.*]] = apply
// CHECK:         [[X_ADDR:%.*]] = struct_element_addr [[SELF_BOX]]#1
// CHECK:         store [[CANARY]] to [[X_ADDR]]
// CHECK:         br bb1
// CHECK:       bb1:
// CHECK:         [[X_ADDR:%.*]] = struct_element_addr [[SELF_BOX]]#1
// CHECK:         strong_release [[CANARY]]
// CHECK:         [[SELF:%.*]] = enum $Optional<FailableStruct>, #Optional.None!enumelt
// CHECK:         br bb2
// CHECK:       bb2:
// CHECK:         dealloc_stack [[SELF_BOX]]#0
// CHECK:         return [[SELF]]
  init?(failAfterPartialInitialization: ()) {
    x = Canary()
    return nil
  }

// CHECK-LABEL: sil hidden @_TFV35definite_init_failable_initializers14FailableStructCfMS0_FT27failAfterFullInitializationT__GSqS0__
// CHECK:       bb0
// CHECK:         [[SELF_BOX:%.*]] = alloc_stack $FailableStruct
// CHECK:         [[CANARY1:%.*]] = apply
// CHECK:         [[X_ADDR:%.*]] = struct_element_addr [[SELF_BOX]]#1
// CHECK:         store [[CANARY1]] to [[X_ADDR]]
// CHECK:         [[CANARY2:%.*]] = apply
// CHECK:         [[Y_ADDR:%.*]] = struct_element_addr [[SELF_BOX]]#1
// CHECK:         store [[CANARY2]] to [[Y_ADDR]]
// CHECK:         br bb1
// CHECK:       bb1:
// CHECK:         [[SELF:%.*]] = struct $FailableStruct ([[CANARY1]] : $Canary, [[CANARY2]] : $Canary)
// CHECK:         release_value [[SELF]]
// CHECK:         [[NEW_SELF:%.*]] = enum $Optional<FailableStruct>, #Optional.None!enumelt
// CHECK:         br bb2
// CHECK:       bb2:
// CHECK:         dealloc_stack [[SELF_BOX]]#0
// CHECK:         return [[NEW_SELF]]
  init?(failAfterFullInitialization: ()) {
    x = Canary()
    y = Canary()
    return nil
  }

// CHECK-LABEL: sil hidden @_TFV35definite_init_failable_initializers14FailableStructCfMS0_FT46failAfterWholeObjectInitializationByAssignmentT__GSqS0__
// CHECK:       bb0
// CHECK:         [[SELF_BOX:%.*]] = alloc_stack $FailableStruct
// CHECK:         [[CANARY]] = apply
// CHECK:         store [[CANARY]] to [[SELF_BOX]]#1
// CHECK:         br bb1
// CHECK:       bb1:
// CHECK:         release_value [[CANARY]]
// CHECK:         [[SELF_VALUE:%.*]] = enum $Optional<FailableStruct>, #Optional.None!enumelt
// CHECK:         br bb2
// CHECK:       bb2:
// CHECK:         dealloc_stack [[SELF_BOX]]#0
// CHECK:         return [[SELF_VALUE]]
  init?(failAfterWholeObjectInitializationByAssignment: ()) {
    self = FailableStruct(noFail: ())
    return nil
  }

// CHECK-LABEL: sil hidden @_TFV35definite_init_failable_initializers14FailableStructCfMS0_FT46failAfterWholeObjectInitializationByDelegationT__GSqS0__
// CHECK:       bb0
// CHECK:         [[SELF_BOX:%.*]] = alloc_stack $FailableStruct
// CHECK:         [[INIT_FN:%.*]] = function_ref @_TFV35definite_init_failable_initializers14FailableStructCfMS0_FT6noFailT__S0_
// CHECK:         [[NEW_SELF:%.*]] = apply [[INIT_FN]](%0)
// CHECK:         store [[NEW_SELF]] to [[SELF_BOX]]#1
// CHECK:         br bb1
// CHECK:       bb1:
// CHECK:         release_value [[NEW_SELF]]
// CHECK:         [[NEW_SELF:%.*]] = enum $Optional<FailableStruct>, #Optional.None!enumelt
// CHECK:         br bb2
// CHECK:       bb2:
// CHECK:         dealloc_stack [[SELF_BOX]]#0
// CHECK:         return [[NEW_SELF]]
  init?(failAfterWholeObjectInitializationByDelegation: ()) {
    self.init(noFail: ())
    return nil
  }

// CHECK-LABEL: sil hidden @_TFV35definite_init_failable_initializers14FailableStructCfMS0_FT20failDuringDelegationT__GSqS0__
// CHECK:       bb0
// CHECK:         [[SELF_BOX:%.*]] = alloc_stack $FailableStruct
// CHECK:         [[INIT_FN:%.*]] = function_ref @_TFV35definite_init_failable_initializers14FailableStructCfMS0_FT24failBeforeInitializationT__GSqS0__
// CHECK:         [[SELF_OPTIONAL:%.*]] = apply [[INIT_FN]](%0)
// CHECK:         [[COND:%.*]] = select_enum [[SELF_OPTIONAL]]
// CHECK:         cond_br [[COND]], bb1, bb2
// CHECK:       bb1:
// CHECK:         [[SELF_VALUE:%.*]] = unchecked_enum_data [[SELF_OPTIONAL]]
// CHECK:         store [[SELF_VALUE]] to [[SELF_BOX]]#1
// CHECK:         [[NEW_SELF:%.*]] = enum $Optional<FailableStruct>, #Optional.Some!enumelt.1, [[SELF_VALUE]]
// CHECK:         br bb3([[NEW_SELF]] : $Optional<FailableStruct>)
// CHECK:       bb2:
// CHECK:         [[NEW_SELF:%.*]] = enum $Optional<FailableStruct>, #Optional.None!enumelt
// CHECK:         br bb3([[NEW_SELF]] : $Optional<FailableStruct>)
// CHECK:       bb3([[NEW_SELF:%.*]] : $Optional<FailableStruct>)
// CHECK:         dealloc_stack [[SELF_BOX]]#0
// CHECK:         return [[NEW_SELF]]
  // Optional to optional
  init?(failDuringDelegation: ()) {
    self.init(failBeforeInitialization: ())
  }

  // IUO to optional
  init!(failDuringDelegation2: ()) {
    self.init(failBeforeInitialization: ())! // unnecessary-but-correct '!'
  }

  // IUO to IUO
  init!(failDuringDelegation3: ()) {
    self.init(failDuringDelegation2: ())! // unnecessary-but-correct '!'
  }

  // non-optional to optional
  init(failDuringDelegation4: ()) {
    self.init(failBeforeInitialization: ())! // necessary '!'
  }

  // non-optional to IUO
  init(failDuringDelegation5: ()) {
    self.init(failDuringDelegation2: ())! // unnecessary-but-correct '!'
  }
}

extension FailableStruct {
  init?(failInExtension: ()) {
    self.init(failInExtension: failInExtension)
  }

  init?(assignInExtension: ()) {
    self = FailableStruct(noFail: ())
  }
}

struct FailableAddrOnlyStruct<T : Pachyderm> {
  var x, y: T

  init(noFail: ()) {
    x = T()
    y = T()
  }

// CHECK-LABEL: sil hidden @_TFV35definite_init_failable_initializers22FailableAddrOnlyStructCuRq_S_9Pachyderm_fMGS0_q__FT24failBeforeInitializationT__GSqGS0_q___
// CHECK:       bb0(%0 : $*Optional<FailableAddrOnlyStruct<T>>, %1 : $@thin FailableAddrOnlyStruct<T>.Type):
// CHECK:         [[SELF_BOX:%.*]] = alloc_stack $FailableAddrOnlyStruct<T>
// CHECK:         br bb1
// CHECK:       bb1:
// CHECK:         inject_enum_addr %0
// CHECK:         br bb2
// CHECK:       bb2:
// CHECK:         dealloc_stack [[SELF_BOX]]#0
// CHECK:         return
  init?(failBeforeInitialization: ()) {
    return nil
  }

// CHECK-LABEL: sil hidden @_TFV35definite_init_failable_initializers22FailableAddrOnlyStructCuRq_S_9Pachyderm_fMGS0_q__FT30failAfterPartialInitializationT__GSqGS0_q___
// CHECK:       bb0(%0 : $*Optional<FailableAddrOnlyStruct<T>>, %1 : $@thin FailableAddrOnlyStruct<T>.Type):
// CHECK:         [[SELF_BOX:%.*]] = alloc_stack $FailableAddrOnlyStruct<T>
// CHECK:         [[T_INIT_FN:%.*]] = witness_method $T, #Pachyderm.init!allocator.1
// CHECK:         [[T_TYPE:%.*]] = metatype $@thick T.Type
// CHECK:         [[X_BOX:%.*]] = alloc_stack $T
// CHECK:         apply [[T_INIT_FN]]<T>([[X_BOX]]#1, [[T_TYPE]])
// CHECK:         [[X_ADDR:%.*]] = struct_element_addr [[SELF_BOX]]#1
// CHECK:         copy_addr [take] [[X_BOX]]#1 to [initialization] [[X_ADDR]]
// CHECK:         dealloc_stack [[X_BOX]]
// CHECK:         br bb1
// CHECK:       bb1:
// CHECK:         [[X_ADDR:%.*]] = struct_element_addr [[SELF_BOX]]#1
// CHECK:         destroy_addr [[X_ADDR]]
// CHECK:         inject_enum_addr %0
// CHECK:         br bb2
// CHECK:       bb2:
// CHECK:         dealloc_stack [[SELF_BOX]]#0
// CHECK:         return
  init?(failAfterPartialInitialization: ()) {
    x = T()
    return nil
  }

// CHECK-LABEL: sil hidden @_TFV35definite_init_failable_initializers22FailableAddrOnlyStructCuRq_S_9Pachyderm_fMGS0_q__FT27failAfterFullInitializationT__GSqGS0_q___
// CHECK:       bb0(%0 : $*Optional<FailableAddrOnlyStruct<T>>, %1 : $@thin FailableAddrOnlyStruct<T>.Type):
// CHECK:         [[SELF_BOX:%.*]] = alloc_stack $FailableAddrOnlyStruct<T>
// CHECK:         [[T_INIT_FN:%.*]] = witness_method $T, #Pachyderm.init!allocator.1
// CHECK:         [[T_TYPE:%.*]] = metatype $@thick T.Type
// CHECK:         [[X_BOX:%.*]] = alloc_stack $T
// CHECK:         apply [[T_INIT_FN]]<T>([[X_BOX]]#1, [[T_TYPE]])
// CHECK:         [[X_ADDR:%.*]] = struct_element_addr [[SELF_BOX]]#1
// CHECK:         copy_addr [take] [[X_BOX]]#1 to [initialization] [[X_ADDR]]
// CHECK:         dealloc_stack [[X_BOX]]#0
// CHECK:         [[T_INIT_FN:%.*]] = witness_method $T, #Pachyderm.init!allocator.1
// CHECK:         [[T_TYPE:%.*]] = metatype $@thick T.Type
// CHECK:         [[Y_BOX:%.*]] = alloc_stack $T
// CHECK:         apply [[T_INIT_FN]]<T>([[Y_BOX]]#1, [[T_TYPE]])
// CHECK:         [[Y_ADDR:%.*]] = struct_element_addr [[SELF_BOX]]#1
// CHECK:         copy_addr [take] [[Y_BOX]]#1 to [initialization] [[Y_ADDR]]
// CHECK:         dealloc_stack [[Y_BOX]]#0
// CHECK:         br bb1
// CHECK:       bb1:
// CHECK:         destroy_addr [[SELF_BOX]]#1
// CHECK:         inject_enum_addr %0
// CHECK:         br bb2
// CHECK:       bb2:
// CHECK:         dealloc_stack [[SELF_BOX]]#0
// CHECK:         return
  init?(failAfterFullInitialization: ()) {
    x = T()
    y = T()
    return nil
  }

  init?(failAfterWholeObjectInitializationByAssignment: ()) {
    self = FailableAddrOnlyStruct(noFail: ())
    return nil
  }

  init?(failAfterWholeObjectInitializationByDelegation: ()) {
    self.init(noFail: ())
    return nil
  }

  // Optional to optional
  init?(failDuringDelegation: ()) {
    self.init(failBeforeInitialization: ())
  }

  // IUO to optional
  init!(failDuringDelegation2: ()) {
    self.init(failBeforeInitialization: ())! // unnecessary-but-correct '!'
  }

  // non-optional to optional
  init(failDuringDelegation3: ()) {
    self.init(failBeforeInitialization: ())! // necessary '!'
  }

  // non-optional to IUO
  init(failDuringDelegation4: ()) {
    self.init(failDuringDelegation2: ())! // unnecessary-but-correct '!'
  }
}

extension FailableAddrOnlyStruct {
  init?(failInExtension: ()) {
    self.init(failBeforeInitialization: failInExtension)
  }

  init?(assignInExtension: ()) {
    self = FailableAddrOnlyStruct(noFail: ())
  }
}

////
// Structs with throwing initializers
////

func unwrap(x: Int) throws -> Int { return x }

struct ThrowStruct {
  var x: Canary

  init(fail: ()) throws { x = Canary() }

  init(noFail: ()) { x = Canary() }

// CHECK-LABEL: sil hidden @_TFV35definite_init_failable_initializers11ThrowStructCfMS0_FzT20failBeforeDelegationSi_S0_
// CHECK:       bb0(%0 : $Int, %1 : $@thin ThrowStruct.Type):
// CHECK:         [[SELF_BOX:%.*]] = alloc_stack $ThrowStruct
// CHECK:         [[UNWRAP_FN:%.*]] = function_ref @_TF35definite_init_failable_initializers6unwrapFzSiSi
// CHECK:         try_apply [[UNWRAP_FN]](%0)
// CHECK:       bb1([[RESULT:%.*]] : $Int):
// CHECK:         [[INIT_FN:%.*]] = function_ref @_TFV35definite_init_failable_initializers11ThrowStructCfMS0_FT6noFailT__S0_
// CHECK:         [[NEW_SELF:%.*]] = apply [[INIT_FN]](%1)
// CHECK:         store [[NEW_SELF]] to [[SELF_BOX]]#1
// CHECK:         dealloc_stack [[SELF_BOX]]#0
// CHECK:         return [[NEW_SELF]]
// CHECK:       bb2([[ERROR:%.*]] : $ErrorType):
// CHECK:         dealloc_stack [[SELF_BOX]]#0
// CHECK:         throw [[ERROR]]
  init(failBeforeDelegation: Int) throws {
    try unwrap(failBeforeDelegation)
    self.init(noFail: ())
  }

// CHECK-LABEL: sil hidden @_TFV35definite_init_failable_initializers11ThrowStructCfMS0_FzT28failBeforeOrDuringDelegationSi_S0_
// CHECK:       bb0(%0 : $Int, %1 : $@thin ThrowStruct.Type):
// CHECK:         [[SELF_BOX:%.*]] = alloc_stack $ThrowStruct
// CHECK:         [[UNWRAP_FN:%.*]] = function_ref @_TF35definite_init_failable_initializers6unwrapFzSiSi
// CHECK:         try_apply [[UNWRAP_FN]](%0)
// CHECK:       bb1([[RESULT:%.*]] : $Int):
// CHECK:         [[INIT_FN:%.*]] = function_ref @_TFV35definite_init_failable_initializers11ThrowStructCfMS0_FzT4failT__S0_
// CHECK:         try_apply [[INIT_FN]](%1)
// CHECK:       bb2([[NEW_SELF:%.*]] : $ThrowStruct):
// CHECK:         store [[NEW_SELF]] to [[SELF_BOX]]#1
// CHECK:         dealloc_stack [[SELF_BOX]]#0
// CHECK:         return [[NEW_SELF]]
// CHECK:       bb3([[ERROR:%.*]] : $ErrorType):
// CHECK:         br bb5([[ERROR]] : $ErrorType)
// CHECK:       bb4([[ERROR:%.*]] : $ErrorType):
// CHECK:         br bb5([[ERROR]] : $ErrorType)
// CHECK:       bb5([[ERROR:%.*]] : $ErrorType):
// CHECK:         dealloc_stack [[SELF_BOX]]#0
// CHECK:         throw [[ERROR]]
  init(failBeforeOrDuringDelegation: Int) throws {
    try unwrap(failBeforeOrDuringDelegation)
    try self.init(fail: ())
  }

// CHECK-LABEL: sil hidden @_TFV35definite_init_failable_initializers11ThrowStructCfMS0_FzT29failBeforeOrDuringDelegation2Si_S0_
// CHECK:       bb0(%0 : $Int, %1 : $@thin ThrowStruct.Type):
// CHECK:         [[SELF_BOX:%.*]] = alloc_stack $ThrowStruct
// CHECK:         [[INIT_FN:%.*]] = function_ref @_TFV35definite_init_failable_initializers11ThrowStructCfMS0_FzT20failBeforeDelegationSi_S0_
// CHECK:         [[UNWRAP_FN:%.*]] = function_ref @_TF35definite_init_failable_initializers6unwrapFzSiSi
// CHECK:         try_apply [[UNWRAP_FN]](%0)
// CHECK:       bb1([[RESULT:%.*]] : $Int):
// CHECK:         try_apply [[INIT_FN]]([[RESULT]], %1)
// CHECK:       bb2([[NEW_SELF:%.*]] : $ThrowStruct):
// CHECK:         store [[NEW_SELF]] to [[SELF_BOX]]#1
// CHECK:         dealloc_stack [[SELF_BOX]]#0
// CHECK:         return [[NEW_SELF]]
// CHECK:       bb3([[ERROR:%.*]] : $ErrorType):
// CHECK:         br bb5([[ERROR]] : $ErrorType)
// CHECK:       bb4([[ERROR:%.*]] : $ErrorType):
// CHECK:         br bb5([[ERROR]] : $ErrorType)
// CHECK:       bb5([[ERROR:%.*]] : $ErrorType):
// CHECK:         dealloc_stack [[SELF_BOX]]#0
// CHECK:         throw [[ERROR]]
  init(failBeforeOrDuringDelegation2: Int) throws {
    try self.init(failBeforeDelegation: unwrap(failBeforeOrDuringDelegation2))
  }

// CHECK-LABEL: sil hidden @_TFV35definite_init_failable_initializers11ThrowStructCfMS0_FzT20failDuringDelegationSi_S0_
// CHECK:       bb0(%0 : $Int, %1 : $@thin ThrowStruct.Type):
// CHECK:         [[SELF_BOX:%.*]] = alloc_stack $ThrowStruct
// CHECK:         [[INIT_FN:%.*]] = function_ref @_TFV35definite_init_failable_initializers11ThrowStructCfMS0_FzT4failT__S0_
// CHECK:         try_apply [[INIT_FN]](%1)
// CHECK:       bb1([[NEW_SELF:%.*]] : $ThrowStruct):
// CHECK:         store [[NEW_SELF]] to [[SELF_BOX]]#1
// CHECK:         dealloc_stack [[SELF_BOX]]#0
// CHECK:         return [[NEW_SELF]]
// CHECK:       bb2([[ERROR:%.*]] : $ErrorType):
// CHECK:         dealloc_stack [[SELF_BOX]]#0
// CHECK:         throw [[ERROR]]
  init(failDuringDelegation: Int) throws {
    try self.init(fail: ())
  }

// CHECK-LABEL: sil hidden @_TFV35definite_init_failable_initializers11ThrowStructCfMS0_FzT19failAfterDelegationSi_S0_
// CHECK:       bb0(%0 : $Int, %1 : $@thin ThrowStruct.Type):
// CHECK:         [[SELF_BOX:%.*]] = alloc_stack $ThrowStruct
// CHECK:         [[INIT_FN:%.*]] = function_ref @_TFV35definite_init_failable_initializers11ThrowStructCfMS0_FT6noFailT__S0_
// CHECK:         [[NEW_SELF:%.*]] = apply [[INIT_FN]](%1)
// CHECK:         store [[NEW_SELF]] to [[SELF_BOX]]#1
// CHECK:         [[UNWRAP_FN:%.*]] = function_ref @_TF35definite_init_failable_initializers6unwrapFzSiSi
// CHECK:         try_apply [[UNWRAP_FN]](%0)
// CHECK:       bb1([[RESULT:%.*]] : $Int):
// CHECK:         dealloc_stack [[SELF_BOX]]#0
// CHECK:         return [[NEW_SELF]]
// CHECK:       bb2([[ERROR:%.*]] : $ErrorType):
// CHECK:         release_value [[NEW_SELF]]
// CHECK:         dealloc_stack [[SELF_BOX]]#0
// CHECK:         throw [[ERROR]]
  init(failAfterDelegation: Int) throws {
    self.init(noFail: ())
    try unwrap(failAfterDelegation)
  }

// CHECK-LABEL: sil hidden @_TFV35definite_init_failable_initializers11ThrowStructCfMS0_FzT27failDuringOrAfterDelegationSi_S0_
// CHECK:       bb0(%0 : $Int, %1 : $@thin ThrowStruct.Type):
// CHECK:         [[BITMAP_BOX:%.*]] = alloc_stack $Builtin.Int1
// CHECK:         [[SELF_BOX:%.*]] = alloc_stack $ThrowStruct
// CHECK:         [[ZERO:%.*]] = integer_literal $Builtin.Int1, 0
// CHECK:         store [[ZERO]] to [[BITMAP_BOX]]#1
// CHECK:         [[INIT_FN:%.*]] = function_ref @_TFV35definite_init_failable_initializers11ThrowStructCfMS0_FzT4failT__S0_
// CHECK:         try_apply [[INIT_FN]](%1)
// CHECK:       bb1([[NEW_SELF:.*]] : $ThrowStruct):
// CHECK:         [[BIT:%.*]] = integer_literal $Builtin.Int1, -1
// CHECK:         store [[BIT]] to [[BITMAP_BOX]]#1
// CHECK:         store [[NEW_SELF]] to [[SELF_BOX]]#1
// CHECK:         [[UNWRAP_FN:%.*]] = function_ref @_TF35definite_init_failable_initializers6unwrapFzSiSi
// CHECK:         try_apply [[UNWRAP_FN]](%0)
// CHECK:       bb2([[RESULT:%.*]] : $Int):
// CHECK:         dealloc_stack [[SELF_BOX]]#0
// CHECK:         dealloc_stack [[BITMAP_BOX]]#0
// CHECK:         return [[NEW_SELF]]
// CHECK:       bb3([[ERROR:%.*]] : $ErrorType):
// CHECK:         br bb5([[ERROR]] : $ErrorType)
// CHECK:       bb4([[ERROR:%.*]] : $ErrorType):
// CHECK:         br bb5([[ERROR]] : $ErrorType)
// CHECK:       bb5([[ERROR:%.*]] : $ErrorType):
// CHECK:         [[COND:%.*]] = load [[BITMAP_BOX]]#1
// CHECK:         cond_br [[COND]], bb6, bb7
// CHECK:       bb6:
// CHECK:         destroy_addr [[SELF_BOX]]#1
// CHECK:         br bb8
// CHECK:       bb7:
// CHECK:         br bb8
// CHECK:       bb8:
// CHECK:         dealloc_stack [[SELF_BOX]]#0
// CHECK:         dealloc_stack [[BITMAP_BOX]]#0
// CHECK:         throw [[ERROR]]
  init(failDuringOrAfterDelegation: Int) throws {
    try self.init(fail: ())
    try unwrap(failDuringOrAfterDelegation)
  }

// CHECK-LABEL: sil hidden @_TFV35definite_init_failable_initializers11ThrowStructCfMS0_FzT27failBeforeOrAfterDelegationSi_S0_
// CHECK:       bb0(%0 : $Int, %1 : $@thin ThrowStruct.Type):
// CHECK:         [[BITMAP_BOX:%.*]] = alloc_stack $Builtin.Int1
// CHECK:         [[SELF_BOX:%.*]] = alloc_stack $ThrowStruct
// CHECK:         [[ZERO:%.*]] = integer_literal $Builtin.Int1, 0
// CHECK:         store [[ZERO]] to [[BITMAP_BOX]]#1
// CHECK:         [[UNWRAP_FN:%.*]] = function_ref @_TF35definite_init_failable_initializers6unwrapFzSiSi
// CHECK:         try_apply [[UNWRAP_FN]](%0)
// CHECK:       bb1([[RESULT:%.*]] : $Int):
// CHECK:         [[INIT_FN:%.*]] = function_ref @_TFV35definite_init_failable_initializers11ThrowStructCfMS0_FT6noFailT__S0_
// CHECK:         [[NEW_SELF:%.*]] = apply [[INIT_FN]](%1)
// CHECK:         [[BIT:%.*]] = integer_literal $Builtin.Int1, -1
// CHECK:         store [[BIT]] to [[BITMAP_BOX]]#1
// CHECK:         store [[NEW_SELF]] to [[SELF_BOX]]#1
// CHECK:         [[UNWRAP_FN:%.*]] = function_ref @_TF35definite_init_failable_initializers6unwrapFzSiSi
// CHECK:         try_apply [[UNWRAP_FN]](%0)
// CHECK:       bb2([[RESULT:%.*]] : $Int):
// CHECK:         dealloc_stack [[SELF_BOX]]#0
// CHECK:         dealloc_stack [[BITMAP_BOX]]#0
// CHECK:         return [[NEW_SELF]]
// CHECK:       bb3([[ERROR:%.*]] : $ErrorType):
// CHECK:         br bb5([[ERROR]] : $ErrorType)
// CHECK:       bb4([[ERROR:%.*]] : $ErrorType):
// CHECK:         br bb5([[ERROR]] : $ErrorType)
// CHECK:       bb5([[ERROR:%.*]] : $ErrorType):
// CHECK:         [[COND:%.*]] = load [[BITMAP_BOX]]#1
// CHECK:         cond_br [[COND]], bb6, bb7
// CHECK:       bb6:
// CHECK:         destroy_addr [[SELF_BOX]]#1
// CHECK:         br bb8
// CHECK:       bb7:
// CHECK:         br bb8
// CHECK:       bb8:
// CHECK:         dealloc_stack [[SELF_BOX]]#0
// CHECK:         dealloc_stack [[BITMAP_BOX]]#0
// CHECK:         throw [[ERROR]]
  init(failBeforeOrAfterDelegation: Int) throws {
    try unwrap(failBeforeOrAfterDelegation)
    self.init(noFail: ())
    try unwrap(failBeforeOrAfterDelegation)
  }

// CHECK-LABEL: sil hidden @_TFV35definite_init_failable_initializers11ThrowStructCfMS0_FT16throwsToOptionalSi_GSqS0__
// CHECK:       bb0(%0 : $Int, %1 : $@thin ThrowStruct.Type):
// CHECK:         [[SELF_BOX:%.*]] = alloc_stack $ThrowStruct
// CHECK:         [[INIT_FN:%.*]] = function_ref @_TFV35definite_init_failable_initializers11ThrowStructCfMS0_FzT20failDuringDelegationSi_S0_
// CHECK:         try_apply [[INIT_FN]](%0, %1)
// CHECK:       bb1([[NEW_SELF:%.*]] : $ThrowStruct):
// CHECK:         [[SELF_OPTIONAL:%.*]] = enum $Optional<ThrowStruct>, #Optional.Some!enumelt.1, [[NEW_SELF]]
// CHECK:         br bb2([[SELF_OPTIONAL]] : $Optional<ThrowStruct>)
// CHECK:       bb2([[SELF_OPTIONAL:%.*]] : $Optional<ThrowStruct>):
// CHECK:         [[COND:%.*]] = select_enum [[SELF_OPTIONAL]]
// CHECK:         cond_br [[COND]], bb3, bb4
// CHECK:       bb3:
// CHECK:         [[SELF_VALUE:%.*]] = unchecked_enum_data [[SELF_OPTIONAL]]
// CHECK:         store [[SELF_VALUE]] to [[SELF_BOX]]#1
// CHECK:         [[NEW_SELF:%.*]] = enum $Optional<ThrowStruct>, #Optional.Some!enumelt.1, [[SELF_VALUE]]
// CHECK:         br bb5([[NEW_SELF]] : $Optional<ThrowStruct>)
// CHECK:       bb4:
// CHECK:         [[NEW_SELF:%.*]] = enum $Optional<ThrowStruct>, #Optional.None!enumelt
// CHECK:         br bb5([[NEW_SELF]] : $Optional<ThrowStruct>)
// CHECK:       bb5([[NEW_SELF:%.*]] : $Optional<ThrowStruct>):
// CHECK:         dealloc_stack [[SELF_BOX]]#0
// CHECK:         return [[NEW_SELF]] : $Optional<ThrowStruct>
// CHECK:       bb6:
// CHECK:         [[NEW_SELF:%.*]] = enum $Optional<ThrowStruct>, #Optional.None!enumelt
// CHECK:         br bb2([[NEW_SELF]] : $Optional<ThrowStruct>)
// CHECK:       bb7([[ERROR:%.*]] : $ErrorType):
// CHECK:         br bb6
  init?(throwsToOptional: Int) {
    try? self.init(failDuringDelegation: throwsToOptional)
  }

  init(throwsToIUO: Int) {
    try! self.init(failDuringDelegation: throwsToIUO)
  }

  init?(throwsToOptionalThrows: Int) throws {
    try? self.init(fail: ())
  }

  init(throwsOptionalToThrows: Int) throws {
    self.init(throwsToOptional: throwsOptionalToThrows)!
  }

  init?(throwsOptionalToOptional: Int) {
    try! self.init(throwsToOptionalThrows: throwsOptionalToOptional)
  }

  init(failBeforeSelfReplacement: Int) throws {
    try unwrap(failBeforeSelfReplacement)
    self = ThrowStruct(noFail: ())
  }

// CHECK-LABEL: sil hidden @_TFV35definite_init_failable_initializers11ThrowStructCfMS0_FzT25failDuringSelfReplacementSi_S0_
// CHECK:       bb0(%0 : $Int, %1 : $@thin ThrowStruct.Type):
// CHECK:         [[SELF_BOX:%.*]] = alloc_stack $ThrowStruct
// CHECK:         [[INIT_FN:%.*]] = function_ref @_TFV35definite_init_failable_initializers11ThrowStructCfMS0_FzT4failT__S0_
// CHECK:         [[SELF_TYPE:%.*]] = metatype $@thin ThrowStruct.Type
// CHECK:         try_apply [[INIT_FN]]([[SELF_TYPE]])
// CHECK:       bb1([[NEW_SELF:%.*]] : $ThrowStruct):
// CHECK:         store [[NEW_SELF]] to [[SELF_BOX]]#1
// CHECK:         dealloc_stack [[SELF_BOX]]#0
// CHECK:         return [[NEW_SELF]]
// CHECK:       bb2([[ERROR:%.*]] : $ErrorType):
// CHECK:         dealloc_stack [[SELF_BOX]]#0
// CHECK:         throw [[ERROR]]
  init(failDuringSelfReplacement: Int) throws {
    try self = ThrowStruct(fail: ())
  }

// CHECK-LABEL: sil hidden @_TFV35definite_init_failable_initializers11ThrowStructCfMS0_FzT24failAfterSelfReplacementSi_S0_
// CHECK:       bb0(%0 : $Int, %1 : $@thin ThrowStruct.Type):
// CHECK:         [[SELF_BOX:%.*]] = alloc_stack $ThrowStruct
// CHECK:         [[INIT_FN:%.*]] = function_ref @_TFV35definite_init_failable_initializers11ThrowStructCfMS0_FT6noFailT__S0_
// CHECK:         [[SELF_TYPE:%.*]] = metatype $@thin ThrowStruct.Type
// CHECK:         [[NEW_SELF:%.*]] = apply [[INIT_FN]]([[SELF_TYPE]])
// CHECK:         store [[NEW_SELF]] to [[SELF_BOX]]#1
// CHECK:         [[UNWRAP_FN:%.*]] = function_ref @_TF35definite_init_failable_initializers6unwrapFzSiSi
// CHECK:         try_apply [[UNWRAP_FN]](%0)
// CHECK:       bb1([[RESULT:%.*]] : $Int):
// CHECK:         dealloc_stack [[SELF_BOX]]#0
// CHECK:         return [[NEW_SELF]]
// CHECK:       bb2([[ERROR:%.*]] : $ErrorType):
// CHECK:         release_value [[NEW_SELF]]
// CHECK:         dealloc_stack [[SELF_BOX]]#0
// CHECK:         throw [[ERROR]]
  init(failAfterSelfReplacement: Int) throws {
    self = ThrowStruct(noFail: ())
    try unwrap(failAfterSelfReplacement)
  }
}

extension ThrowStruct {
  init(failInExtension: ()) throws {
    try self.init(fail: failInExtension)
  }

  init(assignInExtension: ()) throws {
    try self = ThrowStruct(fail: ())
  }
}

struct ThrowAddrOnlyStruct<T : Pachyderm> {
  var x : T

  init(fail: ()) throws { x = T() }

  init(noFail: ()) { x = T() }

  init(failBeforeDelegation: Int) throws {
    try unwrap(failBeforeDelegation)
    self.init(noFail: ())
  }

  init(failBeforeOrDuringDelegation: Int) throws {
    try unwrap(failBeforeOrDuringDelegation)
    try self.init(fail: ())
  }

  init(failBeforeOrDuringDelegation2: Int) throws {
    try self.init(failBeforeDelegation: unwrap(failBeforeOrDuringDelegation2))
  }

  init(failDuringDelegation: Int) throws {
    try self.init(fail: ())
  }

  init(failAfterDelegation: Int) throws {
    self.init(noFail: ())
    try unwrap(failAfterDelegation)
  }

  init(failDuringOrAfterDelegation: Int) throws {
    try self.init(fail: ())
    try unwrap(failDuringOrAfterDelegation)
  }

  init(failBeforeOrAfterDelegation: Int) throws {
    try unwrap(failBeforeOrAfterDelegation)
    self.init(noFail: ())
    try unwrap(failBeforeOrAfterDelegation)
  }

  init?(throwsToOptional: Int) {
    try? self.init(failDuringDelegation: throwsToOptional)
  }

  init(throwsToIUO: Int) {
    try! self.init(failDuringDelegation: throwsToIUO)
  }

  init?(throwsToOptionalThrows: Int) throws {
    try? self.init(fail: ())
  }

  init(throwsOptionalToThrows: Int) throws {
    self.init(throwsToOptional: throwsOptionalToThrows)!
  }

  init?(throwsOptionalToOptional: Int) {
    try! self.init(throwsOptionalToThrows: throwsOptionalToOptional)
  }

  init(failBeforeSelfReplacement: Int) throws {
    try unwrap(failBeforeSelfReplacement)
    self = ThrowAddrOnlyStruct(noFail: ())
  }

  init(failAfterSelfReplacement: Int) throws {
    self = ThrowAddrOnlyStruct(noFail: ())
    try unwrap(failAfterSelfReplacement)
  }
}

extension ThrowAddrOnlyStruct {
  init(failInExtension: ()) throws {
    try self.init(fail: failInExtension)
  }

  init(assignInExtension: ()) throws {
    self = ThrowAddrOnlyStruct(noFail: ())
  }
}

////
// Classes with failable initializers
////

class FailableBaseClass {
  var member: Canary

  init(noFail: ()) {
    member = Canary()
  }

// CHECK-LABEL: sil hidden @_TFC35definite_init_failable_initializers17FailableBaseClasscfMS0_FT27failAfterFullInitializationT__GSqS0__
// CHECK:       bb0(%0 : $FailableBaseClass):
// CHECK:         [[CANARY:%.*]] = apply
// CHECK:         [[MEMBER_ADDR:%.*]] = ref_element_addr %0
// CHECK:         store [[CANARY]] to [[MEMBER_ADDR]]
// CHECK:         br bb1
// CHECK:       bb1:
// CHECK:         strong_release %0
// CHECK:         [[NEW_SELF:%.*]] = enum $Optional<FailableBaseClass>, #Optional.None!enumelt
// CHECK:         br bb2
// CHECK:       bb2:
// CHECK:         return [[NEW_SELF]]
  init?(failAfterFullInitialization: ()) {
    member = Canary()
    return nil
  }

// CHECK-LABEL: sil hidden @_TFC35definite_init_failable_initializers17FailableBaseClasscfMS0_FT20failBeforeDelegationT__GSqS0__
// CHECK:       bb0(%0 : $FailableBaseClass):
// CHECK:         [[SELF_BOX:%.*]] = alloc_stack $FailableBaseClass
// CHECK:         store %0 to [[SELF_BOX]]#1
// CHECK:         br bb1
// CHECK:       bb1:
// CHECK:         dealloc_ref [constructor] %0
// CHECK:         [[RESULT:%.*]] = enum $Optional<FailableBaseClass>, #Optional.None!enumelt
// CHECK:         br bb2
// CHECK:       bb2:
// CHECK:         dealloc_stack [[SELF_BOX]]#0
// CHECK:         return [[RESULT]]
  convenience init?(failBeforeDelegation: ()) {
    return nil
  }

// CHECK-LABEL: sil hidden @_TFC35definite_init_failable_initializers17FailableBaseClasscfMS0_FT19failAfterDelegationT__GSqS0__
// CHECK:       bb0(%0 : $FailableBaseClass):
// CHECK:         [[SELF_BOX:%.*]] = alloc_stack $FailableBaseClass
// CHECK:         store %0 to [[SELF_BOX]]#1
// CHECK:         [[INIT_FN:%.*]] = class_method %0
// CHECK:         [[NEW_SELF:%.*]] = apply [[INIT_FN]](%0)
// CHECK:         store [[NEW_SELF]] to [[SELF_BOX]]#1
// CHECK:         br bb1
// CHECK:       bb1:
// CHECK:         strong_release [[NEW_SELF]]
// CHECK:         [[RESULT:%.*]] = enum $Optional<FailableBaseClass>, #Optional.None!enumelt
// CHECK:         br bb2
// CHECK:       bb2:
// CHECK:         dealloc_stack [[SELF_BOX]]#0
// CHECK:         return [[RESULT]]
  convenience init?(failAfterDelegation: ()) {
    self.init(noFail: ())
    return nil
  }

// CHECK-LABEL: sil hidden @_TFC35definite_init_failable_initializers17FailableBaseClasscfMS0_FT20failDuringDelegationT__GSqS0__
// CHECK:       bb0(%0 : $FailableBaseClass):
// CHECK:         [[SELF_BOX:%.*]] = alloc_stack $FailableBaseClass
// CHECK:         store %0 to [[SELF_BOX]]#1 : $*FailableBaseClass
// CHECK:         [[INIT_FN:%.*]] = class_method %0
// CHECK:         [[SELF_OPTIONAL:%.*]] = apply [[INIT_FN]](%0)
// CHECK:         [[COND:%.*]] = select_enum [[SELF_OPTIONAL]]
// CHECK:         cond_br [[COND]], bb1, bb2
// CHECK:       bb1:
// CHECK:         [[SELF_VALUE:%.*]] = unchecked_enum_data [[SELF_OPTIONAL]]
// CHECK:         store [[SELF_VALUE]] to [[SELF_BOX]]#1
// CHECK:         [[NEW_SELF:%.*]] = enum $Optional<FailableBaseClass>, #Optional.Some!enumelt.1, [[SELF_VALUE]]
// CHECK:         br bb3([[NEW_SELF]] : $Optional<FailableBaseClass>)
// CHECK:       bb2:
// CHECK:         [[NEW_SELF:%.*]] = enum $Optional<FailableBaseClass>, #Optional.None!enumelt
// CHECK:         br bb3([[NEW_SELF]] : $Optional<FailableBaseClass>)
// CHECK:       bb3([[NEW_SELF:%.*]] : $Optional<FailableBaseClass>):
// CHECK:         dealloc_stack [[SELF_BOX]]#0
// CHECK:         return [[NEW_SELF]]
  // Optional to optional
  convenience init?(failDuringDelegation: ()) {
    self.init(failAfterFullInitialization: ())
  }

  // IUO to optional
  convenience init!(failDuringDelegation2: ()) {
    self.init(failAfterFullInitialization: ())! // unnecessary-but-correct '!'
  }

  // IUO to IUO
  convenience init!(noFailDuringDelegation: ()) {
    self.init(failDuringDelegation2: ())! // unnecessary-but-correct '!'
  }

  // non-optional to optional
  convenience init(noFailDuringDelegation2: ()) {
    self.init(failAfterFullInitialization: ())! // necessary '!'
  }
}

extension FailableBaseClass {
  convenience init?(failInExtension: ()) throws {
    self.init(failAfterFullInitialization: failInExtension)
  }
}

// Chaining to failable initializers in a superclass
class FailableDerivedClass : FailableBaseClass {
  var otherMember: Canary

  init?(derivedFailDuringDelegation: ()) {
    self.otherMember = Canary()
    super.init(failAfterFullInitialization: ())
  }

// CHECK-LABEL: sil hidden @_TFC35definite_init_failable_initializers20FailableDerivedClasscfMS0_FT27derivedFailDuringDelegationT__GSqS0__
// CHECK:       bb0(%0 : $FailableDerivedClass):
// CHECK:         [[SELF_BOX:%.*]] = alloc_stack $FailableDerivedClass
// CHECK:         store %0 to [[SELF_BOX]]#1
// CHECK:         [[CANARY:%.*]] = apply
// CHECK:         [[MEMBER_ADDR:%.*]] = ref_element_addr %0
// CHECK:         store [[CANARY]] to [[MEMBER_ADDR]]
// CHECK:         [[BASE_SELF:%.*]] = upcast %0
// CHECK:         [[INIT_FN:%.*]] = function_ref @_TFC35definite_init_failable_initializers17FailableBaseClasscfMS0_FT27failAfterFullInitializationT__GSqS0__
// CHECK:         [[SELF_OPTIONAL:%.*]] = apply [[INIT_FN]]([[BASE_SELF]])
// CHECK:         [[COND:%.*]] = select_enum [[SELF_OPTIONAL]]
// CHECK:         cond_br [[COND]], bb1, bb2
// CHECK:       bb1:
// CHECK:         [[BASE_SELF_VALUE:%.*]] = unchecked_enum_data [[SELF_OPTIONAL]]
// CHECK:         [[SELF_VALUE:%.*]] = unchecked_ref_cast [[BASE_SELF_VALUE]]
// CHECK:         store [[SELF_VALUE]] to [[SELF_BOX]]#1
// CHECK:         [[NEW_SELF:%.*]] = enum $Optional<FailableDerivedClass>, #Optional.Some!enumelt.1, [[SELF_VALUE]]
// CHECK:         br bb3([[NEW_SELF]] : $Optional<FailableDerivedClass>)
// CHECK:       bb2:
// CHECK:         [[NEW_SELF:%.*]] = enum $Optional<FailableDerivedClass>, #Optional.None!enumelt
// CHECK:         br bb3([[NEW_SELF]] : $Optional<FailableDerivedClass>)
// CHECK:       bb3([[NEW_SELF:%.*]] : $Optional<FailableDerivedClass>):
// CHECK:         dealloc_stack [[SELF_BOX]]#0
// CHECK:         return [[NEW_SELF]] : $Optional<FailableDerivedClass>
  init?(derivedFailAfterDelegation: ()) {
    self.otherMember = Canary()
    super.init(noFail: ())
    return nil
  }

  // non-optional to IUO
  init(derivedNoFailDuringDelegation: ()) {
    self.otherMember = Canary()
    super.init(failAfterFullInitialization: ())! // necessary '!'
  }

  // IUO to IUO
  init!(derivedFailDuringDelegation2: ()) {
    self.otherMember = Canary()
    super.init(failAfterFullInitialization: ())! // unnecessary-but-correct '!'
  }
}

extension FailableDerivedClass {
  convenience init?(derivedFailInExtension: ()) throws {
    self.init(derivedFailDuringDelegation: derivedFailInExtension)
  }
}

////
// Classes with throwing initializers
////

class ThrowBaseClass {
  required init() throws {}
}

class ThrowDerivedClass : ThrowBaseClass {
// CHECK-LABEL: sil hidden @_TFC35definite_init_failable_initializers17ThrowDerivedClasscfMS0_FzT_S0_
// CHECK:       bb0(%0 : $ThrowDerivedClass):
// CHECK:         [[SELF_BOX:%.*]] = alloc_stack $ThrowDerivedClass
// CHECK:         store %0 to [[SELF_BOX]]#1
// CHECK:         [[BASE_SELF:%.*]] = upcast %0
// CHECK:         [[INIT_FN:%.*]] = function_ref @_TFC35definite_init_failable_initializers14ThrowBaseClasscfMS0_FzT_S0_
// CHECK:         try_apply [[INIT_FN]]([[BASE_SELF]])
// CHECK:       bb1([[NEW_SELF:%.*]] : $ThrowBaseClass):
// CHECK:         [[DERIVED_SELF:%.*]] = unchecked_ref_cast [[NEW_SELF]]
// CHECK:         store [[DERIVED_SELF]] to [[SELF_BOX]]#1
// CHECK:         dealloc_stack [[SELF_BOX]]#0
// CHECK:         return [[DERIVED_SELF]]
// CHECK:       bb2([[ERROR:%.*]] : $ErrorType):
// CHECK-NEXT:    dealloc_stack [[SELF_BOX]]#0
// CHECK-NEXT:    throw [[ERROR]]
  required init() throws {
    try super.init()
  }

  init(noFailDuringDelegation: ()) {
    try! super.init()
  }

  convenience init(noFailDuringDelegation2: ()) {
    try! self.init()
  }

// CHECK-LABEL: sil hidden @_TFC35definite_init_failable_initializers17ThrowDerivedClasscfMS0_FzT20failBeforeDelegationSi_S0_
// CHECK:       bb0(%0 : $Int, %1 : $ThrowDerivedClass):
// CHECK:         [[SELF_BOX:%.*]] = alloc_stack $ThrowDerivedClass
// CHECK:         store %1 to [[SELF_BOX]]#1
// CHECK:         [[UNWRAP_FN:%.*]] = function_ref @_TF35definite_init_failable_initializers6unwrapFzSiSi
// CHECK:         try_apply [[UNWRAP_FN]](%0)
// CHECK:       bb1([[ARG:%.*]] : $Int):
// CHECK-NEXT:    [[INIT_FN:%.*]] = class_method %1
// CHECK-NEXT:    [[NEW_SELF:%.*]] = apply [[INIT_FN]](%1)
// CHECK-NEXT:    store [[NEW_SELF]] to [[SELF_BOX]]#1
// CHECK-NEXT:    dealloc_stack [[SELF_BOX]]#0
// CHECK-NEXT:    return [[NEW_SELF]]
// CHECK:       bb2([[ERROR:%.*]] : $ErrorType):
// CHECK-NEXT:    dealloc_ref [constructor] %1
// CHECK-NEXT:    dealloc_stack [[SELF_BOX]]#0
// CHECK-NEXT:    throw [[ERROR]]
  convenience init(failBeforeDelegation: Int) throws {
    try unwrap(failBeforeDelegation)
    self.init(noFailDuringDelegation: ())
  }

// CHECK-LABEL: sil hidden @_TFC35definite_init_failable_initializers17ThrowDerivedClasscfMS0_FzT20failDuringDelegationSi_S0_
// CHECK:       bb0(%0 : $Int, %1 : $ThrowDerivedClass):
// CHECK:         [[SELF_BOX:%.*]] = alloc_stack $ThrowDerivedClass
// CHECK:         store %1 to [[SELF_BOX]]#1
// CHECK:         [[INIT_FN:%.*]] = class_method %1
// CHECK:         try_apply [[INIT_FN]](%1)
// CHECK:       bb1([[NEW_SELF:%.*]] : $ThrowDerivedClass):
// CHECK-NEXT:    store [[NEW_SELF]] to [[SELF_BOX]]#1
// CHECK-NEXT:    dealloc_stack [[SELF_BOX]]#0
// CHECK-NEXT:    return [[NEW_SELF]]
// CHECK:       bb2([[ERROR:%.*]] : $ErrorType):
// CHECK-NEXT:    dealloc_stack [[SELF_BOX]]#0
// CHECK-NEXT:    throw [[ERROR]]
  convenience init(failDuringDelegation: Int) throws {
    try self.init()
  }

// CHECK-LABEL: sil hidden @_TFC35definite_init_failable_initializers17ThrowDerivedClasscfMS0_FzT28failBeforeOrDuringDelegationSi_S0_
// CHECK:       bb0(%0 : $Int, %1 : $ThrowDerivedClass):
// CHECK:         [[BITMAP_BOX:%.*]] = alloc_stack $Builtin.Int2
// CHECK:         [[SELF_BOX:%.*]] = alloc_stack $ThrowDerivedClass
// CHECK:         [[ZERO:%.*]] = integer_literal $Builtin.Int2, 0
// CHECK:         store [[ZERO]] to [[BITMAP_BOX]]#1 : $*Builtin.Int2
// CHECK:         store %1 to [[SELF_BOX]]#1
// CHECK:         [[UNWRAP_FN:%.*]] = function_ref @_TF35definite_init_failable_initializers6unwrapFzSiSi
// CHECK:         try_apply [[UNWRAP_FN]](%0)
// CHECK:       bb1([[ARG:%.*]] : $Int):
// CHECK-NEXT:    [[INIT_FN:%.*]] = class_method %1
// CHECK-NEXT:    [[BIT:%.*]] = integer_literal $Builtin.Int2, 1
// CHECK-NEXT:    store [[BIT]] to [[BITMAP_BOX]]#1
// CHECK-NEXT:    try_apply [[INIT_FN]](%1)
// CHECK:       bb2([[NEW_SELF:%.*]] : $ThrowDerivedClass):
// CHECK-NEXT:    store [[NEW_SELF]] to [[SELF_BOX]]#1
// CHECK-NEXT:    dealloc_stack [[SELF_BOX]]#0
// CHECK-NEXT:    dealloc_stack [[BITMAP_BOX]]#0
// CHECK-NEXT:    return [[NEW_SELF]]
// CHECK:       bb3([[ERROR:%.*]] : $ErrorType):
// CHECK-NEXT:    br bb5([[ERROR]] : $ErrorType)
// CHECK:       bb4([[ERROR:%.*]] : $ErrorType):
// CHECK-NEXT:    [[BIT:%.*]] = integer_literal $Builtin.Int2, -1
// CHECK-NEXT:    store [[BIT]] to [[BITMAP_BOX]]#1
// CHECK-NEXT:    br bb5([[ERROR]] : $ErrorType)
// CHECK:       bb5([[ERROR:%.*]] : $ErrorType):
// CHECK-NEXT:    [[BITMAP_VALUE:%.*]] = load [[BITMAP_BOX]]#1
// CHECK-NEXT:    [[BIT_NUM:%.*]] = integer_literal $Builtin.Int2, 1
// CHECK-NEXT:    [[BITMAP_MSB:%.*]] = builtin "lshr_Int2"([[BITMAP_VALUE]] : $Builtin.Int2, [[BIT_NUM]] : $Builtin.Int2)
// CHECK-NEXT:    [[CONDITION:%.*]] = builtin "trunc_Int2_Int1"([[BITMAP_MSB]] : $Builtin.Int2)
// CHECK-NEXT:    cond_br [[CONDITION]], bb6, bb7
// CHECK:       bb6:
// CHECK-NEXT:    br bb8
// CHECK:       bb7:
// CHECK-NEXT:    dealloc_ref [constructor] %1
// CHECK-NExT:    br bb8
// CHECK:       bb8:
// CHECK-NEXT:    dealloc_stack [[SELF_BOX]]#0
// CHECK-NEXT:    dealloc_stack [[BITMAP_BOX]]#0
// CHECK-NEXT:    throw [[ERROR]]
  convenience init(failBeforeOrDuringDelegation: Int) throws {
    try unwrap(failBeforeOrDuringDelegation)
    try self.init()
  }

// CHECK-LABEL: sil hidden @_TFC35definite_init_failable_initializers17ThrowDerivedClasscfMS0_FzT29failBeforeOrDuringDelegation2Si_S0_
// CHECK:         bb0(%0 : $Int, %1 : $ThrowDerivedClass):
// CHECK:         [[BITMAP_BOX:%.*]] = alloc_stack $Builtin.Int2
// CHECK:         [[SELF_BOX:%.*]] = alloc_stack $ThrowDerivedClass
// CHECK:         [[ZERO:%.*]] = integer_literal $Builtin.Int2, 0
// CHECK:         store [[ZERO]] to [[BITMAP_BOX]]#1 : $*Builtin.Int2
// CHECK:         store %1 to [[SELF_BOX]]#1
// CHECK-NEXT:    [[INIT_FN:%.*]] = class_method %1
// CHECK:         [[UNWRAP_FN:%.*]] = function_ref @_TF35definite_init_failable_initializers6unwrapFzSiSi
// CHECK:         try_apply [[UNWRAP_FN]](%0)
// CHECK:       bb1([[ARG:%.*]] : $Int):
// CHECK-NEXT:    [[BIT:%.*]] = integer_literal $Builtin.Int2, 1
// CHECK-NEXT:    store [[BIT]] to [[BITMAP_BOX]]#1
// CHECK-NEXT:    try_apply [[INIT_FN]]([[ARG]], %1)
// CHECK:       bb2([[NEW_SELF:%.*]] : $ThrowDerivedClass):
// CHECK-NEXT:    store [[NEW_SELF]] to [[SELF_BOX]]#1
// CHECK-NEXT:    dealloc_stack [[SELF_BOX]]#0
// CHECK-NEXT:    dealloc_stack [[BITMAP_BOX]]#0
// CHECK-NEXT:    return [[NEW_SELF]]
// CHECK:       bb3([[ERROR:%.*]] : $ErrorType):
// CHECK-NEXT:    br bb5([[ERROR]] : $ErrorType)
// CHECK:       bb4([[ERROR:%.*]] : $ErrorType):
// CHECK-NEXT:    [[BIT:%.*]] = integer_literal $Builtin.Int2, -1
// CHECK-NEXT:    store [[BIT]] to [[BITMAP_BOX]]#1
// CHECK-NEXT:    br bb5([[ERROR]] : $ErrorType)
// CHECK:       bb5([[ERROR:%.*]] : $ErrorType):
// CHECK-NEXT:    [[BITMAP_VALUE:%.*]] = load [[BITMAP_BOX]]#1
// CHECK-NEXT:    [[BIT_NUM:%.*]] = integer_literal $Builtin.Int2, 1
// CHECK-NEXT:    [[BITMAP_MSB:%.*]] = builtin "lshr_Int2"([[BITMAP_VALUE]] : $Builtin.Int2, [[BIT_NUM]] : $Builtin.Int2)
// CHECK-NEXT:    [[CONDITION:%.*]] = builtin "trunc_Int2_Int1"([[BITMAP_MSB]] : $Builtin.Int2)
// CHECK-NEXT:    cond_br [[CONDITION]], bb6, bb7
// CHECK:       bb6:
// CHECK-NEXT:    br bb8
// CHECK:       bb7:
// CHECK-NEXT:    dealloc_ref [constructor] %1
// CHECK-NEXT:    br bb8
// CHECK:       bb8:
// CHECK-NEXT:    dealloc_stack [[SELF_BOX]]#0
// CHECK-NEXT:    dealloc_stack [[BITMAP_BOX]]#0
// CHECK-NEXT:    throw [[ERROR]]
  convenience init(failBeforeOrDuringDelegation2: Int) throws {
    try self.init(failBeforeDelegation: unwrap(failBeforeOrDuringDelegation2))
  }

// CHECK-LABEL: sil hidden @_TFC35definite_init_failable_initializers17ThrowDerivedClasscfMS0_FzT19failAfterDelegationSi_S0_
// CHECK:       bb0(%0 : $Int, %1 : $ThrowDerivedClass):
// CHECK:         [[SELF_BOX:%.*]] = alloc_stack $ThrowDerivedClass
// CHECK:         store %1 to [[SELF_BOX]]#1
// CHECK:         [[INIT_FN:%.*]] = class_method %1
// CHECK:         [[NEW_SELF:%.*]] = apply [[INIT_FN]](%1)
// CHECK:         store [[NEW_SELF]] to [[SELF_BOX]]#1
// CHECK:         [[UNWRAP_FN:%.*]] = function_ref @_TF35definite_init_failable_initializers6unwrapFzSiSi
// CHECK:         try_apply [[UNWRAP_FN]](%0)
// CHECK:       bb1([[RESULT:%.*]] : $Int):
// CHECK:         dealloc_stack [[SELF_BOX]]#0
// CHECK:         return [[NEW_SELF]]
// CHECK:       bb2([[ERROR:%.*]] : $ErrorType):
// CHECK:         strong_release [[NEW_SELF]]
// CHECK:         dealloc_stack [[SELF_BOX]]#0
// CHECK:         throw [[ERROR]]
  convenience init(failAfterDelegation: Int) throws {
    self.init(noFailDuringDelegation: ())
    try unwrap(failAfterDelegation)
  }

// CHECK-LABEL: sil hidden @_TFC35definite_init_failable_initializers17ThrowDerivedClasscfMS0_FzT27failDuringOrAfterDelegationSi_S0_
// CHECK:       bb0(%0 : $Int, %1 : $ThrowDerivedClass):
// CHECK:         [[BITMAP_BOX:%.*]] = alloc_stack $Builtin.Int2
// CHECK:         [[SELF_BOX:%.*]] = alloc_stack $ThrowDerivedClass
// CHECK:         [[ZERO:%.*]] = integer_literal $Builtin.Int2, 0
// CHECK:         store [[ZERO]] to [[BITMAP_BOX]]#1
// CHECK:         store %1 to [[SELF_BOX]]#1
// CHECK:         [[INIT_FN:%.*]] = class_method %1
// CHECK:         [[BIT:%.*]] = integer_literal $Builtin.Int2, 1
// CHECK:         store [[BIT]] to [[BITMAP_BOX]]#1
// CHECK:         try_apply [[INIT_FN]](%1)
// CHECK:       bb1([[NEW_SELF:%.*]] : $ThrowDerivedClass):
// CHECK:         store [[NEW_SELF]] to [[SELF_BOX]]#1
// CHECK:         [[UNWRAP_FN:%.*]] = function_ref @_TF35definite_init_failable_initializers6unwrapFzSiSi
// CHECK:         try_apply [[UNWRAP_FN]](%0)
// CHECK:       bb2([[RESULT:%.*]] : $Int):
// CHECK:         dealloc_stack [[SELF_BOX]]#0
// CHECK:         dealloc_stack [[BITMAP_BOX]]#0
// CHECK:         return [[NEW_SELF]]
// CHECK:       bb3([[ERROR:%.*]] : $ErrorType):
// CHECK:         [[BIT:%.*]] = integer_literal $Builtin.Int2, -1
// CHECK:         store [[BIT]] to [[BITMAP_BOX]]#1
// CHECK:         br bb5([[ERROR]] : $ErrorType)
// CHECK:       bb4([[ERROR:%.*]] : $ErrorType):
// CHECK:         br bb5([[ERROR]] : $ErrorType)
// CHECK:       bb5([[ERROR:%.*]] : $ErrorType):
// CHECK:         [[BITMAP:%.*]] = load [[BITMAP_BOX]]#1
// CHECK:         [[ONE:%.*]] = integer_literal $Builtin.Int2, 1
// CHECK:         [[BITMAP_MSB:%.*]] = builtin "lshr_Int2"([[BITMAP]] : $Builtin.Int2, [[ONE]] : $Builtin.Int2)
// CHECK:         [[COND:%.*]] = builtin "trunc_Int2_Int1"([[BITMAP_MSB]] : $Builtin.Int2)
// CHECK:         cond_br [[COND]], bb6, bb7
// CHECK:       bb6:
// CHECK:         br bb8
// CHECK:       bb7:
// CHECK:         destroy_addr [[SELF_BOX]]#1
// CHECK:         br bb8
// CHECK:       bb8:
// CHECK:         dealloc_stack [[SELF_BOX]]#0
// CHECK:         dealloc_stack [[BITMAP_BOX]]#0
// CHECK:         throw [[ERROR]]
  convenience init(failDuringOrAfterDelegation: Int) throws {
    try self.init()
    try unwrap(failDuringOrAfterDelegation)
  }

// CHECK-LABEL: sil hidden @_TFC35definite_init_failable_initializers17ThrowDerivedClasscfMS0_FzT27failBeforeOrAfterDelegationSi_S0_
// CHECK:       bb0(%0 : $Int, %1 : $ThrowDerivedClass):
// CHECK:         [[BITMAP_BOX:%.*]] = alloc_stack $Builtin.Int1
// CHECK:         [[SELF_BOX:%.*]] = alloc_stack $ThrowDerivedClass
// CHECK:         [[ZERO:%.*]] = integer_literal $Builtin.Int1, 0
// CHECK:         store [[ZERO]] to [[BITMAP_BOX]]#1
// CHECK:         store %1 to [[SELF_BOX]]#1
// CHECK:         [[UNWRAP_FN:%.*]] = function_ref @_TF35definite_init_failable_initializers6unwrapFzSiSi
// CHECK:         try_apply [[UNWRAP_FN]](%0)
// CHECK:       bb1([[RESULT:%.*]] : $Int):
// CHECK:         [[INIT_FN:%.*]] = class_method %1
// CHECK:         [[BIT:%.*]] = integer_literal $Builtin.Int1, -1
// CHECK:         store [[BIT]] to [[BITMAP_BOX]]#1
// CHECK:         [[NEW_SELF:%.*]] = apply [[INIT_FN]](%1)
// CHECK:         store [[NEW_SELF]] to [[SELF_BOX]]#1
// CHECK:         [[UNWRAP_FN:%.*]] = function_ref @_TF35definite_init_failable_initializers6unwrapFzSiSi
// CHECK:         try_apply [[UNWRAP_FN]](%0)
// CHECK:       bb2([[RESULT:%.*]] : $Int):
// CHECK:         dealloc_stack [[SELF_BOX]]#0
// CHECK:         dealloc_stack [[BITMAP_BOX]]#0
// CHECK:         return [[NEW_SELF]]
// CHECK:       bb3([[ERROR:%.*]] : $ErrorType):
// CHECK:         br bb5([[ERROR]] : $ErrorType)
// CHECK:       bb4([[ERROR:%.*]] : $ErrorType):
// CHECK:         br bb5([[ERROR]] : $ErrorType)
// CHECK:       bb5([[ERROR:%.*]] : $ErrorType):
// CHECK:         [[COND:%.*]] = load [[BITMAP_BOX]]#1
// CHECK:         cond_br [[COND]], bb6, bb7
// CHECK:       bb6:
// CHECK:         destroy_addr [[SELF_BOX]]#1
// CHECK:         br bb8
// CHECK:       bb7:
// CHECK:         [[OLD_SELF:%.*]] = load [[SELF_BOX]]#1
// CHECK:         dealloc_ref [constructor] [[OLD_SELF]]
// CHECK:         br bb8
// CHECK:       bb8:
// CHECK:         dealloc_stack [[SELF_BOX]]
// CHECK:         dealloc_stack [[BITMAP_BOX]]
// CHECK:         throw [[ERROR]]
  convenience init(failBeforeOrAfterDelegation: Int) throws {
    try unwrap(failBeforeOrAfterDelegation)
    self.init(noFailDuringDelegation: ())
    try unwrap(failBeforeOrAfterDelegation)
  }
}

////
// Enums with failable initializers
////

enum FailableEnum {
  case A

  init?(a: Int64) { self = .A }

  init!(b: Int64) {
    self.init(a: b)! // unnecessary-but-correct '!'
  }

  init(c: Int64) {
    self.init(a: c)! // necessary '!'
  }

  init(d: Int64) {
    self.init(b: d)! // unnecessary-but-correct '!'
  }
}

////
// Protocols and protocol extensions
////

// Delegating to failable initializers from a protocol extension to a
// protocol.
protocol P1 {
  init?(p1: Int64)
}

extension P1 {
  init!(p1a: Int64) {
    self.init(p1: p1a)! // unnecessary-but-correct '!'
  }

  init(p1b: Int64) {
    self.init(p1: p1b)! // necessary '!'
  }
}

protocol P2 : class {
  init?(p2: Int64)
}

extension P2 {
  init!(p2a: Int64) {
    self.init(p2: p2a)! // unnecessary-but-correct '!'
  }

  init(p2b: Int64) {
    self.init(p2: p2b)! // necessary '!'
  }
}

@objc protocol P3 {
  init?(p3: Int64)
}

extension P3 {
  init!(p3a: Int64) {
    self.init(p3: p3a)! // unnecessary-but-correct '!'
  }

  init(p3b: Int64) {
    self.init(p3: p3b)! // necessary '!'
  }
}

// Delegating to failable initializers from a protocol extension to a
// protocol extension.
extension P1 {
  init?(p1c: Int64) {
    self.init(p1: p1c)
  }

  init!(p1d: Int64) {
    self.init(p1c: p1d)! // unnecessary-but-correct '!'
  }

  init(p1e: Int64) {
    self.init(p1c: p1e)! // necessary '!'
  }
}

extension P2 {
  init?(p2c: Int64) {
    self.init(p2: p2c)
  }

  init!(p2d: Int64) {
    self.init(p2c: p2d)! // unnecessary-but-correct '!'
  }

  init(p2e: Int64) {
    self.init(p2c: p2e)! // necessary '!'
  }
}

////
// self.dynamicType with uninitialized self
////

func use(a : Any) {}

class DynamicTypeBase {
  var x: Int

  init() {
    use(self.dynamicType)
    x = 0
  }

  convenience init(a : Int) {
    use(self.dynamicType)
    self.init()
  }
}

class DynamicTypeDerived : DynamicTypeBase {
  override init() {
    use(self.dynamicType)
    super.init()
  }

  convenience init(a : Int) {
    use(self.dynamicType)
    self.init()
  }
}

struct DynamicTypeStruct {
  var x: Int

  init() {
    use(self.dynamicType)
    x = 0
  }

  init(a : Int) {
    use(self.dynamicType)
    self.init()
  }
}
