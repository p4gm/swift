//===--- Index.cpp --------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2016 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#include "swift/Index/Index.h"

#include "swift/AST/AST.h"
#include "swift/AST/SourceEntityWalker.h"
#include "swift/AST/USRGeneration.h"
#include "swift/Basic/SourceManager.h"
#include "swift/Basic/StringExtras.h"
#include "llvm/ADT/APInt.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/Support/FileSystem.h"

using namespace swift;
using namespace swift::index;

static SymbolSubKind getSubKindForAccessor(AccessorKind AK) {
  switch (AK) {
    case AccessorKind::NotAccessor: return SymbolSubKind::None;
    case AccessorKind::IsGetter:    return SymbolSubKind::AccessorGetter;
    case AccessorKind::IsSetter:    return SymbolSubKind::AccessorSetter;
    case AccessorKind::IsWillSet:   return SymbolSubKind::AccessorWillSet;
    case AccessorKind::IsDidSet:    return SymbolSubKind::AccessorDidSet;
    case AccessorKind::IsAddressor: return SymbolSubKind::AccessorAddressor;
    case AccessorKind::IsMutableAddressor:
      return SymbolSubKind::AccessorMutableAddressor;
    case AccessorKind::IsMaterializeForSet:
      llvm_unreachable("unexpected MaterializeForSet");
  }

  llvm_unreachable("Unhandled AccessorKind in switch.");
}

static bool
printArtificialName(const swift::AbstractStorageDecl *ASD, AccessorKind AK, llvm::raw_ostream &OS) {
  switch (AK) {
  case AccessorKind::IsGetter:
    OS << "getter:" << ASD->getFullName();
    return false;
  case AccessorKind::IsSetter:
    OS << "setter:" << ASD->getFullName();
    return false;
  case AccessorKind::IsDidSet:
    OS << "didSet:" << ASD->getFullName();
    return false;
  case AccessorKind::IsWillSet:
    OS << "willSet:" << ASD->getFullName() ;
    return false;

  case AccessorKind::NotAccessor:
  case AccessorKind::IsMaterializeForSet:
  case AccessorKind::IsAddressor:
  case AccessorKind::IsMutableAddressor:
    return true;
  }

  llvm_unreachable("Unhandled AccessorKind in switch.");
}

static bool printDisplayName(const swift::ValueDecl *D, llvm::raw_ostream &OS) {
  if (!D->hasName()) {
    auto *FD = dyn_cast<FuncDecl>(D);
    if (!FD || FD->getAccessorKind() == AccessorKind::NotAccessor)
      return true;
    return printArtificialName(FD->getAccessorStorageDecl(), FD->getAccessorKind(), OS);
  }

  OS << D->getFullName();
  return false;
}

namespace {
// Adapter providing a common interface for a SourceFile/Module.
class SourceFileOrModule {
  llvm::PointerUnion<SourceFile *, Module *> SFOrMod;

public:
  SourceFileOrModule(SourceFile &SF) : SFOrMod(&SF) {}
  SourceFileOrModule(Module &Mod) : SFOrMod(&Mod) {}

  SourceFile *getAsSourceFile() const {
    return SFOrMod.dyn_cast<SourceFile *>();
  }

  Module *getAsModule() const { return SFOrMod.dyn_cast<Module *>(); }

  Module &getModule() const {
    if (auto SF = SFOrMod.dyn_cast<SourceFile *>())
      return *SF->getParentModule();
    return *SFOrMod.get<Module *>();
  }

  ArrayRef<FileUnit *> getFiles() const {
    return SFOrMod.is<SourceFile *>() ? *SFOrMod.getAddrOfPtr1()
                                      : SFOrMod.get<Module *>()->getFiles();
  }

  StringRef getFilename() const {
    if (SourceFile *SF = SFOrMod.dyn_cast<SourceFile *>())
      return SF->getFilename();
    return SFOrMod.get<Module *>()->getModuleFilename();
  }

  void
  getImportedModules(SmallVectorImpl<Module::ImportedModule> &Modules) const {
    if (SourceFile *SF = SFOrMod.dyn_cast<SourceFile *>()) {
      SF->getImportedModules(Modules, Module::ImportFilter::All);
    } else {
      SFOrMod.get<Module *>()->getImportedModules(Modules,
                                                  Module::ImportFilter::All);
    }
  }
};

class IndexSwiftASTWalker : public SourceEntityWalker {
  IndexDataConsumer &IdxConsumer;
  SourceManager &SrcMgr;
  unsigned BufferID;
  bool enableWarnings;

  bool IsModuleFile = false;
  bool isSystemModule = false;
  struct Entity {
    Decl *D;
    SymbolKind Kind;
    SymbolSubKindSet SubKinds;
    SymbolRoleSet Roles;
    SmallVector<SourceLoc, 6> RefsToSuppress;
  };
  SmallVector<Entity, 6> EntitiesStack;
  SmallVector<Expr *, 8> ExprStack;
  bool Cancelled = false;

  struct NameAndUSR {
    StringRef USR;
    StringRef name;
  };
  typedef llvm::PointerIntPair<Decl *, 3> DeclAccessorPair;
  llvm::DenseMap<Decl *, NameAndUSR> nameAndUSRCache;
  llvm::DenseMap<DeclAccessorPair, NameAndUSR> accessorNameAndUSRCache;
  StringScratchSpace stringStorage;

  bool getNameAndUSR(ValueDecl *D, StringRef &name, StringRef &USR) {
    auto &result = nameAndUSRCache[D];
    if (result.USR.empty()) {
      SmallString<128> storage;
      {
        llvm::raw_svector_ostream OS(storage);
        if (ide::printDeclUSR(D, OS))
          return true;
        result.USR = stringStorage.copyString(OS.str());
      }

      storage.clear();
      {
        llvm::raw_svector_ostream OS(storage);
        printDisplayName(D, OS);
        result.name = stringStorage.copyString(OS.str());
      }
    }

    name = result.name;
    USR = result.USR;
    return false;
  }

  bool getPseudoAccessorNameAndUSR(AbstractStorageDecl *D, AccessorKind AK, StringRef &Name, StringRef &USR) {
    assert(AK != AccessorKind::NotAccessor);
    assert(static_cast<int>(AK) < 0x111 && "AccessorKind too big for pair");
    DeclAccessorPair key(D, static_cast<int>(AK));
    auto &result = accessorNameAndUSRCache[key];
    if (result.USR.empty()) {
      SmallString<128> storage;
      {
        llvm::raw_svector_ostream OS(storage);
        if(ide::printAccessorUSR(D, AK, OS))
          return true;
        result.USR = stringStorage.copyString(OS.str());
      }

      storage.clear();
      {
        llvm::raw_svector_ostream OS(storage);
        printArtificialName(D, AK, OS);
        result.name = stringStorage.copyString(OS.str());
      }
    }

    Name = result.name;
    USR = result.USR;
    return false;
  }

  bool addRelation(IndexSymbol &Info, SymbolRoleSet RelationRoles, ValueDecl *D) {
    assert(D);
    StringRef Name, USR;
    SymbolKind Kind = getSymbolKindForDecl(D);
    SymbolSubKindSet SubKinds = 0;

    if (Kind == SymbolKind::Unknown)
      return true;
    if (Kind == SymbolKind::Accessor)
      SubKinds |= getSubKindForAccessor(cast<FuncDecl>(D)->getAccessorKind());
    if (getNameAndUSR(D, Name, USR))
      return true;

    Info.Relations.push_back(IndexRelation(RelationRoles, D, Kind, SubKinds, Name, USR));
    Info.roles |= RelationRoles;
    return false;
  }



public:
  IndexSwiftASTWalker(IndexDataConsumer &IdxConsumer, ASTContext &Ctx,
                      unsigned BufferID)
      : IdxConsumer(IdxConsumer), SrcMgr(Ctx.SourceMgr), BufferID(BufferID),
        enableWarnings(IdxConsumer.enableWarnings()) {}
  ~IndexSwiftASTWalker() override { assert(Cancelled || EntitiesStack.empty()); }

  void visitModule(Module &Mod, StringRef Hash);

private:
  bool visitImports(SourceFileOrModule Mod,
                    llvm::SmallPtrSet<Module *, 16> &Visited);

  bool handleSourceOrModuleFile(SourceFileOrModule SFOrMod, StringRef KnownHash,
                                bool &HashIsKnown);

  bool walkToDeclPre(Decl *D, CharSourceRange Range) override {
    // Do not handle unavailable decls.
    if (AvailableAttr::isUnavailable(D))
      return false;
    if (FuncDecl *FD = dyn_cast<FuncDecl>(D)) {
      if (FD->isAccessor() && getParentDecl() != FD->getAccessorStorageDecl())
        return false; // already handled as part of the var decl.
    }
    if (ValueDecl *VD = dyn_cast<ValueDecl>(D)) {
      if (!report(VD))
        return false;
      if (SubscriptDecl *SD = dyn_cast<SubscriptDecl>(VD)) {
        // Avoid indexing the indices, only walk the getter/setter.
        if (SD->getGetter())
          if (SourceEntityWalker::walk(cast<Decl>(SD->getGetter())))
            return false;
        if (SD->getSetter())
          if (SourceEntityWalker::walk(cast<Decl>(SD->getSetter())))
            return false;
        if (SD->hasAddressors()) {
          if (auto FD = SD->getAddressor())
            SourceEntityWalker::walk(cast<Decl>(FD));
          if (Cancelled)
            return false;
          if (auto FD = SD->getMutableAddressor())
            SourceEntityWalker::walk(cast<Decl>(FD));
        }
        walkToDeclPost(D);
        return false; // already walked what we needed.
      }
    }
    if (ExtensionDecl *ED = dyn_cast<ExtensionDecl>(D))
      return reportExtension(ED);
    return true;
  }

  bool walkToDeclPost(Decl *D) override {
    if (Cancelled)
      return false;

    if (getParentDecl() == D)
      return finishCurrentEntity();

    return true;
  }

  bool walkToExprPre(Expr *E) override {
    if (Cancelled)
      return false;
    ExprStack.push_back(E);
    return true;
  }

  bool walkToExprPost(Expr *E) override {
    if (Cancelled)
      return false;
    assert(ExprStack.back() == E);
    ExprStack.pop_back();
    return true;
  }

  bool visitDeclReference(ValueDecl *D, CharSourceRange Range,
                          TypeDecl *CtorTyRef, Type T,
                          SemaReferenceKind Kind) override {
    SourceLoc Loc = Range.getStart();

    if (isRepressed(Loc) || Loc.isInvalid())
      return true;

    IndexSymbol Info;
    if (CtorTyRef)
      if (!reportRef(CtorTyRef, Loc, Info))
        return false;
    if (!reportRef(D, Loc, Info))
      return false;

    return true;
  }

  Decl *getParentDecl() {
    if (!EntitiesStack.empty())
      return EntitiesStack.back().D;
    return nullptr;
  }

  void repressRefAtLoc(SourceLoc Loc) {
    assert(!EntitiesStack.empty());
    EntitiesStack.back().RefsToSuppress.push_back(Loc);
  }

  bool isRepressed(SourceLoc Loc) {
    if (EntitiesStack.empty())
      return false;
    auto &Suppressed = EntitiesStack.back().RefsToSuppress;
    return std::find(Suppressed.begin(), Suppressed.end(), Loc) != Suppressed.end();

  }

  Expr *getCurrentExpr() {
    return ExprStack.empty() ? nullptr : ExprStack.back();
  }

  Expr *getParentExpr() {
    if (ExprStack.size() >= 2)
      return ExprStack.end()[-2];
    return nullptr;
  }


  bool report(ValueDecl *D);
  bool reportExtension(ExtensionDecl *D);
  bool reportRef(ValueDecl *D, SourceLoc Loc, IndexSymbol &Info);

  bool startEntity(Decl *D, IndexSymbol &Info);
  bool startEntityDecl(ValueDecl *D);

  bool reportRelatedRef(ValueDecl *D, SourceLoc Loc, SymbolRoleSet Relations, ValueDecl *Related);
  bool reportRelatedTypeRef(const TypeLoc &Ty, SymbolRoleSet Relations, ValueDecl *Related);
  bool reportInheritedTypeRefs(ArrayRef<TypeLoc> Inherited, ValueDecl *Inheritee);
  NominalTypeDecl *getTypeLocAsNominalTypeDecl(const TypeLoc &Ty);

  bool reportPseudoGetterDecl(VarDecl *D) {
    return reportPseudoAccessor(D, AccessorKind::IsGetter, /*IsRef=*/false,
                                D->getLoc());
  }
  bool reportPseudoSetterDecl(VarDecl *D) {
    return reportPseudoAccessor(D, AccessorKind::IsSetter, /*IsRef=*/false,
                                D->getLoc());
  }
  bool reportPseudoAccessor(AbstractStorageDecl *D, AccessorKind AccKind,
                            bool IsRef, SourceLoc Loc);

  bool finishCurrentEntity() {
    Entity CurrEnt = EntitiesStack.pop_back_val();
    assert(CurrEnt.Kind != SymbolKind::Unknown);
    if (!IdxConsumer.finishSourceEntity(CurrEnt.Kind, CurrEnt.SubKinds,
                                        CurrEnt.Roles)) {
      Cancelled = true;
      return false;
    }
    return true;
  }

  bool initIndexSymbol(ValueDecl *D, SourceLoc Loc, bool IsRef,
                       IndexSymbol &Info);
  bool initFuncDeclIndexSymbol(ValueDecl *D, IndexSymbol &Info);
  bool initCallRefIndexSymbol(Expr *CurrentE, Expr *ParentE, ValueDecl *D,
                              SourceLoc Loc, IndexSymbol &Info);
  bool initVarRefIndexSymbols(Expr *CurrentE, ValueDecl *D, SourceLoc Loc,
                              IndexSymbol &Info);

  std::pair<unsigned, unsigned> getLineCol(SourceLoc Loc) {
    if (Loc.isInvalid())
      return std::make_pair(0, 0);
    return SrcMgr.getLineAndColumn(Loc, BufferID);
  }

  bool shouldIndex(ValueDecl *D) const {
    if (D->isImplicit())
      return false;
    if (isLocal(D))
      return false;
    if (D->isPrivateStdlibDecl())
      return false;

    return true;
  }

  bool isLocal(ValueDecl *D) const {
    return D->getDeclContext()->getLocalContext();
  }

  void getModuleHash(SourceFileOrModule SFOrMod, llvm::raw_ostream &OS);
  llvm::hash_code hashModule(llvm::hash_code code, SourceFileOrModule SFOrMod);
  llvm::hash_code hashFileReference(llvm::hash_code code,
                                    SourceFileOrModule SFOrMod);
  void getRecursiveModuleImports(Module &Mod,
                                 SmallVectorImpl<Module *> &Imports);
  void collectRecursiveModuleImports(Module &Mod,
                                     llvm::SmallPtrSet<Module *, 16> &Visited);

  template <typename F>
  void warn(F log) {
    if (!enableWarnings)
      return;

    SmallString<128> warning;
    llvm::raw_svector_ostream OS(warning);
    log(OS);
  }

  // This maps a module to all its imports, recursively.
  llvm::DenseMap<Module *, llvm::SmallVector<Module *, 4>> ImportsMap;
};
} // anonymous namespace

void IndexSwiftASTWalker::visitModule(Module &Mod, StringRef KnownHash) {
  SourceFile *SrcFile = nullptr;
  for (auto File : Mod.getFiles()) {
    if (auto SF = dyn_cast<SourceFile>(File)) {
      auto BufID = SF->getBufferID();
      if (BufID.hasValue() && *BufID == BufferID) {
        SrcFile = SF;
        break;
      }
    }
  }

  bool HashIsKnown;
  if (SrcFile != nullptr) {
    IsModuleFile = false;
    if (!handleSourceOrModuleFile(*SrcFile, KnownHash, HashIsKnown))
      return;
    if (HashIsKnown)
      return; // No need to report symbols.
    walk(*SrcFile);
  } else {
    IsModuleFile = true;
    isSystemModule = Mod.isSystemModule();
    if (!handleSourceOrModuleFile(Mod, KnownHash, HashIsKnown))
      return;
    if (HashIsKnown)
      return; // No need to report symbols.
    walk(Mod);
  }
}

bool IndexSwiftASTWalker::handleSourceOrModuleFile(SourceFileOrModule SFOrMod,
                                                   StringRef KnownHash,
                                                   bool &HashIsKnown) {
  // Common reporting for TU/module file.

  SmallString<32> HashBuf;
  {
    llvm::raw_svector_ostream HashOS(HashBuf);
    getModuleHash(SFOrMod, HashOS);
    StringRef Hash = HashOS.str();
    HashIsKnown = Hash == KnownHash;
    if (!IdxConsumer.recordHash(Hash, HashIsKnown))
      return false;
  }

  // We always report the dependencies, even if the hash is known.
  llvm::SmallPtrSet<Module *, 16> Visited;
  return visitImports(SFOrMod, Visited);
}

bool IndexSwiftASTWalker::visitImports(
    SourceFileOrModule TopMod, llvm::SmallPtrSet<Module *, 16> &Visited) {
  // Dependencies of the stdlib module (like SwiftShims module) are
  // implementation details.
  if (TopMod.getModule().isStdlibModule())
    return true;

  bool IsNew = Visited.insert(&TopMod.getModule()).second;
  if (!IsNew)
    return true;

  SmallVector<Module::ImportedModule, 8> Imports;
  TopMod.getImportedModules(Imports);

  llvm::SmallPtrSet<Module *, 8> Reported;
  for (auto Import : Imports) {
    Module *Mod = Import.second;
    bool NewReport = Reported.insert(Mod).second;
    if (!NewReport)
      continue;

    // FIXME: Handle modules with multiple source files; these will fail on
    // getModuleFilename() (by returning an empty path). Note that such modules
    // may be heterogeneous.
    StringRef Path = Mod->getModuleFilename();
    if (Path.empty() || Path == TopMod.getFilename())
      continue; // this is a submodule.

    SymbolKind ImportKind = SymbolKind::Unknown;
    for (auto File : Mod->getFiles()) {
      switch (File->getKind()) {
      case FileUnitKind::Source:
      case FileUnitKind::Builtin:
      case FileUnitKind::Derived:
        break;
      case FileUnitKind::SerializedAST:
        assert(ImportKind == SymbolKind::Unknown &&
               "cannot handle multi-file modules");
        ImportKind = SymbolKind::Module;
        break;
      case FileUnitKind::ClangModule:
        assert(ImportKind == SymbolKind::Unknown &&
               "cannot handle multi-file modules");
        ImportKind = SymbolKind::ClangModule;
        break;
      }
    }
    if (ImportKind == SymbolKind::Unknown)
      continue;

    StringRef Hash;
    SmallString<32> HashBuf;
    if (ImportKind != SymbolKind::ClangModule) {
      llvm::raw_svector_ostream HashOS(HashBuf);
      getModuleHash(*Mod, HashOS);
      Hash = HashOS.str();
    }

    if (!IdxConsumer.startDependency(ImportKind, Mod->getName().str(), Path,
                                     Mod->isSystemModule(), Hash))
      return false;
    if (ImportKind != SymbolKind::ClangModule)
      if (!visitImports(*Mod, Visited))
        return false;
    if (!IdxConsumer.finishDependency(ImportKind))
      return false;
  }

  return true;
}

bool IndexSwiftASTWalker::startEntity(Decl *D, IndexSymbol &Info) {
  switch (IdxConsumer.startSourceEntity(Info)) {
    case swift::index::IndexDataConsumer::Abort:
      Cancelled = true;
      LLVM_FALLTHROUGH;
    case swift::index::IndexDataConsumer::Skip:
      return false;
    case swift::index::IndexDataConsumer::Continue:
      EntitiesStack.push_back({D, Info.kind, Info.subKinds, Info.roles, {}});
      return true;
  }
}

bool IndexSwiftASTWalker::startEntityDecl(ValueDecl *D) {
  if (!shouldIndex(D))
    return false;

  SourceLoc Loc = D->getLoc();
  if (Loc.isInvalid() && !IsModuleFile)
    return false;

  IndexSymbol Info;
  if (isa<FuncDecl>(D)) {
    if (initFuncDeclIndexSymbol(D, Info))
      return false;
  } else {
    if (initIndexSymbol(D, Loc, /*IsRef=*/false, Info))
      return false;
  }

  if (auto Overridden = D->getOverriddenDecl()) {
    if (addRelation(Info, (SymbolRoleSet) SymbolRole::RelationOverrideOf, Overridden))
      return false;
  }
  for (auto Conf : D->getSatisfiedProtocolRequirements()) {
    if (addRelation(Info, (SymbolRoleSet) SymbolRole::RelationOverrideOf, Conf))
      return false;
  }

  if (auto Parent = getParentDecl()) {
    // FIXME handle extensions properly
    if (auto ParentVD = dyn_cast<ValueDecl>(Parent)) {
      SymbolRoleSet RelationsToParent = (SymbolRoleSet)SymbolRole::RelationChildOf;
      if (Info.kind == SymbolKind::Accessor)
        RelationsToParent |= (SymbolRoleSet)SymbolRole::RelationAccessorOf;
      if (addRelation(Info, RelationsToParent, ParentVD))
        return false;

    } else if (auto ParentED = dyn_cast<ExtensionDecl>(Parent)) {
      if (NominalTypeDecl *NTD = ParentED->getExtendedType()->getAnyNominal()) {
        if (addRelation(Info, (SymbolRoleSet) SymbolRole::RelationChildOf, NTD))
          return false;
      }
    }
  }

  return startEntity(D, Info);
}

bool IndexSwiftASTWalker::reportRelatedRef(ValueDecl *D, SourceLoc Loc, SymbolRoleSet Relations, ValueDecl *Related) {
  if (!shouldIndex(D))
    return true;

  IndexSymbol Info;
  if (addRelation(Info, Relations, Related))
    return true;

  // don't report this ref again when visitDeclReference reports it
  repressRefAtLoc(Loc);

  if(!reportRef(D, Loc, Info)) {
    Cancelled = true;
    return false;
  }

  return !Cancelled;
}

bool IndexSwiftASTWalker::reportInheritedTypeRefs(ArrayRef<TypeLoc> Inherited, ValueDecl *Inheritee) {
  for (auto Base : Inherited) {
    if(!reportRelatedTypeRef(Base, (SymbolRoleSet) SymbolRole::RelationBaseOf, Inheritee))
      return false;
  }
  return true;
}

bool IndexSwiftASTWalker::reportRelatedTypeRef(const TypeLoc &Ty, SymbolRoleSet Relations, ValueDecl *Related) {

  if (IdentTypeRepr *T = dyn_cast_or_null<IdentTypeRepr>(Ty.getTypeRepr())) {
    auto Comps = T->getComponentRange();
    if (auto NTD =
            dyn_cast_or_null<NominalTypeDecl>(Comps.back()->getBoundDecl())) {
      if (!reportRelatedRef(NTD, Comps.back()->getIdLoc(), Relations, Related))
        return false;
    }
    return true;
  }

  if (Ty.getType()) {
    if (auto nominal = Ty.getType()->getAnyNominal())
      if (!reportRelatedRef(nominal, Ty.getLoc(), Relations, Related))
        return false;
  }
  return true;
}

bool IndexSwiftASTWalker::reportPseudoAccessor(AbstractStorageDecl *D,
                                               AccessorKind AccKind, bool IsRef,
                                               SourceLoc Loc) {
  if (!shouldIndex(D))
    return true; // continue walking.

  auto updateInfo = [this, D, AccKind](IndexSymbol &Info) {
    if (getPseudoAccessorNameAndUSR(D, AccKind, Info.name, Info.USR))
      return true;
    Info.kind = SymbolKind::Accessor;
    Info.subKinds |= getSubKindForAccessor(AccKind);
    Info.roles |= (SymbolRoleSet)SymbolRole::Implicit;
    Info.group = "";
    return false;
  };

  if (IsRef) {
    IndexSymbol Info;
    if (initCallRefIndexSymbol(ExprStack.back(), getParentExpr(), D, Loc, Info))
      return true; // continue walking.
    if (updateInfo(Info))
      return true;

    if (!IdxConsumer.startSourceEntity(Info) || !IdxConsumer.finishSourceEntity(Info.kind, Info.subKinds, Info.roles))
      Cancelled = true;
  } else {
    IndexSymbol Info;
    if (initIndexSymbol(D, Loc, IsRef, Info))
      return true; // continue walking.
    if (updateInfo(Info))
      return true;
    if (addRelation(Info, (SymbolRoleSet) SymbolRole::RelationAccessorOf, D))
      return true;

    if (!IdxConsumer.startSourceEntity(Info) || !IdxConsumer.finishSourceEntity(Info.kind, Info.subKinds, Info.roles))
      Cancelled = true;
  }
  return !Cancelled;
}

NominalTypeDecl *
IndexSwiftASTWalker::getTypeLocAsNominalTypeDecl(const TypeLoc &Ty) {
  if (Type T = Ty.getType())
    return T->getAnyNominal();
  if (IdentTypeRepr *T = dyn_cast_or_null<IdentTypeRepr>(Ty.getTypeRepr())) {
    auto Comp = T->getComponentRange().back();
    if (auto NTD = dyn_cast_or_null<NominalTypeDecl>(Comp->getBoundDecl()))
      return NTD;
  }
  return nullptr;
}

bool IndexSwiftASTWalker::reportExtension(ExtensionDecl *D) {
  SourceLoc Loc = D->getExtendedTypeLoc().getSourceRange().Start;
  if (!D->getExtendedType())
    return true;
  NominalTypeDecl *NTD = D->getExtendedType()->getAnyNominal();
  if (!NTD)
    return true;
  if (!shouldIndex(NTD))
    return true;

  IndexSymbol Info;
  if (initIndexSymbol(NTD, Loc, /*IsRef=*/false, Info))
    return true;

  Info.kind = getSymbolKindForDecl(D);
  if (isa<StructDecl>(NTD))
    Info.subKinds |= SymbolSubKind::ExtensionOfStruct;
  else if (isa<ClassDecl>(NTD))
    Info.subKinds |= SymbolSubKind::ExtensionOfClass;
  else if (isa<EnumDecl>(NTD))
    Info.subKinds |= SymbolSubKind::ExtensionOfEnum;
  else if (isa<ProtocolDecl>(NTD))
    Info.subKinds |= SymbolSubKind::ExtensionOfProtocol;

  assert(Info.subKinds != 0);

  if (!startEntity(D, Info))
    return false;

  // FIXME: make extensions their own entity
  if (!reportRelatedRef(NTD, Loc, (SymbolRoleSet)SymbolRole::RelationExtendedBy,
                        NTD))
      return false;
  if (!reportInheritedTypeRefs(D->getInherited(), NTD))
      return false;

  return true;
}

bool IndexSwiftASTWalker::report(ValueDecl *D) {
  if (startEntityDecl(D)) {
    // Pass accessors.
    if (auto VarD = dyn_cast<VarDecl>(D)) {
      if (!VarD->getGetter() && !VarD->getSetter()) {
        // No actual getter or setter, pass 'pseudo' accessors.
        // We create accessor entities so we can implement the functionality
        // of libclang, which reports implicit method property accessor
        // declarations, invocations, and overrides for properties.
        // Note that an ObjC class subclassing from a Swift class, may still
        // be able to override its non-computed-property-accessors via a
        // method.
        if (!reportPseudoGetterDecl(VarD))
          return false;
        if (!reportPseudoSetterDecl(VarD))
          return false;
      } else {
        if (auto FD = VarD->getGetter())
          SourceEntityWalker::walk(cast<Decl>(FD));
        if (Cancelled)
          return false;
        if (auto FD = VarD->getSetter())
          SourceEntityWalker::walk(cast<Decl>(FD));
        if (Cancelled)
          return false;
        if (VarD->hasObservers()) {
          if (auto FD = VarD->getWillSetFunc())
            SourceEntityWalker::walk(cast<Decl>(FD));
          if (Cancelled)
            return false;
          if (auto FD = VarD->getDidSetFunc())
            SourceEntityWalker::walk(cast<Decl>(FD));
          if (Cancelled)
            return false;
        }
        if (VarD->hasAddressors()) {
          if (auto FD = VarD->getAddressor())
            SourceEntityWalker::walk(cast<Decl>(FD));
          if (Cancelled)
            return false;
          if (auto FD = VarD->getMutableAddressor())
            SourceEntityWalker::walk(cast<Decl>(FD));
        }
      }
    } else if (auto NTD = dyn_cast<NominalTypeDecl>(D)) {
      if (!reportInheritedTypeRefs(NTD->getInherited(), NTD))
        return false;
    }
  }

  return !Cancelled;
}

//
bool IndexSwiftASTWalker::reportRef(ValueDecl *D, SourceLoc Loc,
                                    IndexSymbol &Info) {
  if (!shouldIndex(D))
    return true; // keep walking

  if (isa<AbstractFunctionDecl>(D)) {
    if (initCallRefIndexSymbol(getCurrentExpr(), getParentExpr(), D, Loc, Info))
      return true;
  } else if (isa<AbstractStorageDecl>(D)) {
    if (initVarRefIndexSymbols(getCurrentExpr(), D, Loc, Info))
      return true;
  } else {
    if (initIndexSymbol(D, Loc, /*isRef=*/true, Info))
      return true;
  }


  if (!startEntity(D, Info)) {
    return true;
  }

  // Report the accessors that were utilized.
  if (isa<AbstractStorageDecl>(D)) {
    bool UsesGetter = Info.roles & (SymbolRoleSet)SymbolRole::Read;
    bool UsesSetter = Info.roles & (SymbolRoleSet)SymbolRole::Write;

    AbstractStorageDecl *ASD = cast<AbstractStorageDecl>(D);
    if (UsesGetter)
      if (!reportPseudoAccessor(ASD, AccessorKind::IsGetter, /*IsRef=*/true,
                                Loc))
        return false;
    if (UsesSetter)
      if (!reportPseudoAccessor(ASD, AccessorKind::IsSetter, /*IsRef=*/true,
                                Loc))
        return false;
  }

  return finishCurrentEntity();
}

bool IndexSwiftASTWalker::initIndexSymbol(ValueDecl *D, SourceLoc Loc,
                                          bool IsRef, IndexSymbol &Info) {
  assert(D);
  Info.decl = D;
  Info.kind = getSymbolKindForDecl(D);
  if (Info.kind == SymbolKind::Unknown)
    return true;

  if (Info.kind == SymbolKind::Accessor)
    Info.subKinds |= getSubKindForAccessor(cast<FuncDecl>(D)->getAccessorKind());
  // Cannot be extension, which is not a ValueDecl.

  if (IsRef)
    Info.roles |= (unsigned)SymbolRole::Reference;
  else
    Info.roles |= (unsigned)SymbolRole::Definition;

  if (getNameAndUSR(D, Info.name, Info.USR))
    return true;

  std::tie(Info.line, Info.column) = getLineCol(Loc);
  if (!IsRef) {
    if (auto Group = D->getGroupName())
      Info.group = Group.getValue();
  }
  return false;
}

static NominalTypeDecl *getNominalParent(ValueDecl *D) {
  Type Ty = D->getDeclContext()->getDeclaredTypeOfContext();
  if (!Ty)
    return nullptr;
  return Ty->getAnyNominal();
}

static bool isTestCandidate(ValueDecl *D) {
  if (!D->hasName())
    return false;

  // A 'test candidate' is:
  // 1. An instance method...
  auto FD = dyn_cast<FuncDecl>(D);
  if (!FD)
    return false;
  if (!D->isInstanceMember())
    return false;

  // 2. ...on a class or extension (not a struct)...
  auto parentNTD = getNominalParent(D);
  if (!parentNTD)
    return false;
  if (!isa<ClassDecl>(parentNTD))
    return false;

  // 3. ...that returns void...
  Type RetTy = FD->getResultInterfaceType();
  if (RetTy && !RetTy->isVoid())
    return false;

  // 4. ...takes no parameters...
  if (FD->getParameterLists().size() != 2)
    return false;
  if (FD->getParameterList(1)->size() != 0)
    return false;

  // 5. ...is of at least 'internal' accessibility (unless we can use
  //    Objective-C reflection)...
  if (!D->getASTContext().LangOpts.EnableObjCInterop &&
      (D->getFormalAccess() < Accessibility::Internal ||
      parentNTD->getFormalAccess() < Accessibility::Internal))
    return false;

  // 6. ...and starts with "test".
  if (FD->getName().str().startswith("test"))
    return true;

  return false;
}

bool IndexSwiftASTWalker::initFuncDeclIndexSymbol(ValueDecl *D,
                                                  IndexSymbol &Info) {
  if (initIndexSymbol(D, D->getLoc(), /*IsRef=*/false, Info))
    return true;

  if (isTestCandidate(D))
    Info.subKinds |= SymbolSubKind::UnitTest;

  if (auto Group = D->getGroupName())
    Info.group = Group.getValue();
  return false;
}

static bool isSuperRefExpr(Expr *E) {
  if (!E)
    return false;
  if (isa<SuperRefExpr>(E))
    return true;
  if (auto LoadE = dyn_cast<LoadExpr>(E))
    return isSuperRefExpr(LoadE->getSubExpr());
  return false;
}

static bool isDynamicCall(Expr *BaseE, ValueDecl *D) {
  // The call is 'dynamic' if the method is not of a struct and the
  // receiver is not 'super'. Note that if the receiver is 'super' that
  // does not mean that the call is statically determined (an extension
  // method may have injected itself in the super hierarchy).
  // For our purposes 'dynamic' means that the method call cannot invoke
  // a method in a subclass.
  auto TyD = getNominalParent(D);
  if (!TyD)
    return false;
  if (isa<StructDecl>(TyD))
    return false;
  if (isSuperRefExpr(BaseE))
    return false;
  if (BaseE->getType()->is<MetatypeType>())
    return false;

  return true;
}

bool IndexSwiftASTWalker::initCallRefIndexSymbol(Expr *CurrentE, Expr *ParentE,
                                                 ValueDecl *D, SourceLoc Loc,
                                                 IndexSymbol &Info) {
  if (!ParentE)
    return true;

  if (initIndexSymbol(D, Loc, /*IsRef=*/true, Info))
    return true;

  Info.roles |= (unsigned)SymbolRole::Call;

  Decl *ParentD = getParentDecl();
  if (ParentD && isa<ValueDecl>(ParentD)) {
    if (addRelation(Info, (SymbolRoleSet) SymbolRole::RelationCalledBy, cast<ValueDecl>(ParentD)))
        return true;
  }

  Expr *BaseE = nullptr;
  if (auto DotE = dyn_cast<DotSyntaxCallExpr>(ParentE))
    BaseE = DotE->getBase();
  else if (auto MembE = dyn_cast<MemberRefExpr>(CurrentE))
    BaseE = MembE->getBase();
  else if (auto SubsE = dyn_cast<SubscriptExpr>(CurrentE))
    BaseE = SubsE->getBase();

  if (!BaseE || BaseE == CurrentE)
    return false;

  if (Type ReceiverTy = BaseE->getType()) {
    if (auto LVT = ReceiverTy->getAs<LValueType>())
      ReceiverTy = LVT->getObjectType();
    else if (auto MetaT = ReceiverTy->getAs<MetatypeType>())
      ReceiverTy = MetaT->getInstanceType();

    if (auto TyD = ReceiverTy->getAnyNominal()) {
      StringRef unused;
      if (addRelation(Info, (SymbolRoleSet) SymbolRole::RelationReceivedBy, TyD))
        return true;
      if (isDynamicCall(BaseE, D))
        Info.roles |= (unsigned)SymbolRole::Dynamic;
    }
  }

  return false;
}

bool IndexSwiftASTWalker::initVarRefIndexSymbols(Expr *CurrentE, ValueDecl *D, SourceLoc Loc, IndexSymbol &Info) {

  if (!(CurrentE->getReferencedDecl() == D))
    return true;

  if (initIndexSymbol(D, Loc, /*IsRef=*/true, Info))
    return true;

  AccessKind Kind = CurrentE->hasLValueAccessKind() ? CurrentE->getLValueAccessKind() : AccessKind::Read;
  switch (Kind) {
  case swift::AccessKind::Read:
    Info.roles |= (unsigned)SymbolRole::Read;
    break;
  case swift::AccessKind::ReadWrite:
    Info.roles |= (unsigned)SymbolRole::Read;
    LLVM_FALLTHROUGH;
  case swift::AccessKind::Write:
    Info.roles |= (unsigned)SymbolRole::Write;
  }
  
  return false;
}

llvm::hash_code
IndexSwiftASTWalker::hashFileReference(llvm::hash_code code,
                                       SourceFileOrModule SFOrMod) {
  StringRef Filename = SFOrMod.getFilename();
  if (Filename.empty())
    return code;

  // FIXME: FileManager for swift ?

  llvm::sys::fs::file_status Status;
  if (std::error_code Ret = llvm::sys::fs::status(Filename, Status)) {
    // Failure to read the file, just use filename to recover.
    warn([&](llvm::raw_ostream &OS) {
      OS << "failed to stat file: " << Filename << " (" << Ret.message() << ')';
    });
    return hash_combine(code, Filename);
  }

  // Don't use inode because it can easily change when you update the repository
  // even though the file is supposed to be the same (same size/time).
  code = hash_combine(code, Filename);
  return hash_combine(code, Status.getSize(),
                      Status.getLastModificationTime().toEpochTime());
}

llvm::hash_code IndexSwiftASTWalker::hashModule(llvm::hash_code code,
                                                SourceFileOrModule SFOrMod) {
  code = hashFileReference(code, SFOrMod);

  SmallVector<Module *, 16> Imports;
  getRecursiveModuleImports(SFOrMod.getModule(), Imports);
  for (auto Import : Imports)
    code = hashFileReference(code, *Import);

  return code;
}

void IndexSwiftASTWalker::getRecursiveModuleImports(
    Module &Mod, SmallVectorImpl<Module *> &Imports) {
  auto It = ImportsMap.find(&Mod);
  if (It != ImportsMap.end()) {
    Imports.append(It->second.begin(), It->second.end());
    return;
  }

  llvm::SmallPtrSet<Module *, 16> Visited;
  collectRecursiveModuleImports(Mod, Visited);
  Visited.erase(&Mod);

  warn([&Imports](llvm::raw_ostream &OS) {
    std::for_each(Imports.begin(), Imports.end(), [&OS](Module *M) {
      if (M->getModuleFilename().empty()) {
        std::string Info = "swift::Module with empty file name!! \nDetails: \n";
        Info += "  name: ";
        Info += M->getName().get();
        Info += "\n";

        auto Files = M->getFiles();
        std::for_each(Files.begin(), Files.end(), [&](FileUnit *FU) {
          Info += "  file unit: ";

          switch (FU->getKind()) {
          case FileUnitKind::Builtin:
            Info += "builtin";
            break;
          case FileUnitKind::Derived:
            Info += "derived";
            break;
          case FileUnitKind::Source:
            Info += "source, file=\"";
            Info += cast<SourceFile>(FU)->getFilename();
            Info += "\"";
            break;
          case FileUnitKind::SerializedAST:
            Info += "serialized ast, file=\"";
            Info += cast<LoadedFile>(FU)->getFilename();
            Info += "\"";
            break;
          case FileUnitKind::ClangModule:
            Info += "clang module, file=\"";
            Info += cast<LoadedFile>(FU)->getFilename();
            Info += "\"";
          }

          Info += "\n";
        });

        OS << "swift::Module with empty file name! " << Info << "\n";
      }
    });
  });

  Imports.append(Visited.begin(), Visited.end());
  std::sort(Imports.begin(), Imports.end(), [](Module *LHS, Module *RHS) {
    return LHS->getModuleFilename() < RHS->getModuleFilename();
  });

  // Cache it.
  ImportsMap[&Mod].append(Imports.begin(), Imports.end());
}

void IndexSwiftASTWalker::collectRecursiveModuleImports(
    Module &TopMod, llvm::SmallPtrSet<Module *, 16> &Visited) {

  bool IsNew = Visited.insert(&TopMod).second;
  if (!IsNew)
    return;

  // Pure Clang modules are tied to their dependencies, no need to look into its
  // imports.
  // FIXME: What happens if the clang module imports a swift module ? So far
  // the assumption is that the path to the swift module will be fixed, so no
  // need to hash the clang module.
  // FIXME: This is a bit of a hack.
  if (TopMod.getFiles().size() == 1)
    if (TopMod.getFiles().front()->getKind() == FileUnitKind::ClangModule)
      return;

  auto It = ImportsMap.find(&TopMod);
  if (It != ImportsMap.end()) {
    Visited.insert(It->second.begin(), It->second.end());
    return;
  }

  SmallVector<Module::ImportedModule, 8> Imports;
  TopMod.getImportedModules(Imports, Module::ImportFilter::All);

  for (auto Import : Imports) {
    collectRecursiveModuleImports(*Import.second, Visited);
  }
}

void IndexSwiftASTWalker::getModuleHash(SourceFileOrModule Mod,
                                        llvm::raw_ostream &OS) {
  // FIXME: Use a longer hash string to minimize possibility for conflicts.
  llvm::hash_code code = hashModule(0, Mod);
  OS << llvm::APInt(64, code).toString(36, /*Signed=*/false);
}

//===----------------------------------------------------------------------===//
// Indexing entry points
//===----------------------------------------------------------------------===//

void index::indexSourceFile(SourceFile *SF, StringRef hash,
                            IndexDataConsumer &consumer) {
  assert(SF);
  unsigned bufferID = SF->getBufferID().getValue();
  IndexSwiftASTWalker walker(consumer, SF->getASTContext(), bufferID);
  walker.visitModule(*SF->getParentModule(), hash);
  consumer.finish();
}

void index::indexModule(ModuleDecl *module, StringRef hash,
                        IndexDataConsumer &consumer) {
  assert(module);
  IndexSwiftASTWalker walker(consumer, module->getASTContext(),
                             /*bufferID*/ -1);
  walker.visitModule(*module, hash);
  consumer.finish();
}
