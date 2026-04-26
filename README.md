# Workflow-Orchestrated AI Agent Marketplace — Phase 1

Solidity 0.8.20+ contracts for a workflow-orchestrated agent marketplace on 0G Chain.
This bundle implements **Phase 1**: User layer (UserStateINFT + UserStateLedger) and
Agent layer (AgentDiamond facets + AgentFactory + AgentRegistry).

Workflow + Treasury are **Phase 2** and not in this drop. The hooks they need are
already in place — see "Phase 2 plug-in points" below.

---

## What's here

```
contracts/
├── interfaces/
│   ├── IDiamond.sol                  Standard EIP-2535 (FacetCut struct + enum)
│   ├── IDiamondCut.sol               Standard EIP-2535
│   ├── IDiamondLoupe.sol             Standard EIP-2535
│   ├── IERC165.sol                   Standard
│   ├── IERC173.sol                   Standard ownership
│   ├── IERC7857.sol                  Full ERC-7857 surface (mint, secureTransfer,
│   │                                 cloneToken, publish, authorizeUsage, ownerOf,
│   │                                 dataHashOf, encryptedURIOf, getPermissions,
│   │                                 isAuthorized)
│   ├── IERC7857Oracle.sol            Oracle for re-encryption proof verification
│   ├── IUserStateINFT.sol            Protocol-internal surface (tokenIdOf,
│   │                                 ownerOf, isAuthorizedFor)
│   ├── IUserStateLedger.sol          appendItem + StateItem + Visibility enum
│   └── IAgentRegistry.sol            registerAgent / syncAgent + AgentRecord
│
├── libraries/
│   ├── LibDiamond.sol                EIP-2535 internals; verbatim from CoreGame
│   │                                 stack except `isAuthorized` no longer reads
│   │                                 LibGameInfoStorage (so it's reusable here)
│   ├── LibFacetRegistry.sol          Verbatim
│   ├── LibFacetRegistryStorage.sol   Verbatim
│   ├── LibPermissionScope.sol        Typed encode/decode for the `bytes`
│   │                                 permissions blob carried by ERC-7857
│   ├── LibAgentManifestStorage.sol   Diamond storage (manifest fields)
│   ├── LibAgentPermissionStorage.sol Diamond storage (workers + trustedCallers)
│   └── LibAgentExecutionStorage.sol  Diamond storage (request records, ledger
│                                     + iNFT addresses)
│
├── facets/
│   ├── DiamondCutFacet.sol           Owner-gated diamondCut + diamondCutWithName
│   ├── DiamondLoupeFacet.sol         Standard loupe + ERC-165
│   ├── OwnershipFacet.sol            Verbatim
│   ├── FacetRegistryFacet.sol        Verbatim
│   ├── AgentManifestFacet.sol        Init-once manifest, admin-mutable economics
│   ├── AgentPermissionFacet.sol      Manage workers + trusted callers
│   ├── AgentExecutionFacet.sol       request/userRequest → ack → complete/fail/cancel
│   │                                 state machine; writes outputs to UserStateLedger
│   └── AgentAdminFacet.sol           admin() / setAdmin / syncToRegistry
│
├── oracles/
│   └── MockERC7857Oracle.sol         Trust-the-proof oracle for tests
│
├── AgentDiamond.sol                  Verbatim port of CoreGameDiamond (renamed)
├── AgentDiamondShared.sol            InitialFaucets struct
├── AgentFactory.sol                  Single-call deploy + init + register
├── AgentRegistry.sol                 Global, append-only agent index
├── UserStateINFT.sol                 ERC-7857 implementation, one mint per wallet
└── UserStateLedger.sol               Per-iNFT append-only state ledger
```

**Compiles clean** with `solc 0.8.24`, optimizer 200 runs, no warnings.

---

## Locked-in design decisions

These are choices I had to make in the absence of explicit spec direction; they're
worth re-checking before going any further.

### 1. The user authorizes the **agent diamond contract** in UserStateINFT
…not the agent admin EOA. The diamond then internally re-checks worker
authorization against its own permission storage. This means:
- Admin rotation on an agent does **not** invalidate the user's grant.
- Worker rotation on an agent does **not** invalidate the user's grant.
- The user's grant is keyed on the long-lived diamond address, which is
  the right level of trust.

### 2. Type chaining is validated at workflow **creation**, not at run start
This isn't enforced anywhere in Phase 1 (no workflow contract yet), but
`AgentManifestFacet.supportsInput(bytes32 inputType)` is the surface a
WorkflowFactory will call to validate composition.

### 3. Run state is collapsed to a single `RequestStatus` enum
NONE / CREATED / PROCESSING / COMPLETED / FAILED / CANCELLED — no separate
"queued" vs "scheduled" vs "submitted" states. If Phase 2 needs more
granularity it can add intermediate enum values without breaking storage.

### 4. Mid-run permission revoke
On `complete`, the agent re-calls `UserStateINFT.isAuthorizedFor` via
`UserStateLedger.appendItem`. If the user revoked usage during processing,
the ledger reverts, the `complete()` reverts, and the request stays in
PROCESSING / CREATED. The user (for direct requests) or admin can then
`cancel()` it. Phase 2's escrow contract should treat CANCELLED as the
trigger for refund.

### 5. UserStateINFT `secureTransfer` wipes ALL outstanding usage
authorizations on a successful transfer. The new owner inherits a clean
slate. (Most ERC-7857 deployments do this; the spec is silent.)

### 6. UserStateINFT `cloneToken` keeps the original token's executors
intact and starts the new token with no authorizations. The clone
recipient inherits the encrypted URI but a freshly-sealed key.

### 7. Single global UserStateINFT contract, one mint per wallet
Enforced via `walletToTokenId` mapping. The spec said "primary iNFT" so
I read this as one-per-wallet rather than per-game-context.

### 8. Agent facets are deployed once at factory init and reused across
every agent diamond. This is the canonical EIP-2535 pattern (facets are
stateless — per-diamond state lives in diamond storage). It differs from
the CoreGameFactory pattern (which redeployed all facets every time);
that pattern is fine but wastes ~70% of the per-agent gas. Switch back
trivially if you prefer the isolation.

### 9. AgentAdminFacet is **separate** from OwnershipFacet but they
overlap semantically. The admin == diamond owner. AgentAdminFacet adds
`syncToRegistry` and an admin-flavored event. AgentDiamond also defines
`owner()` / `transferOwnership()` / `supportsInterface()` inline (verbatim
from CoreGameDiamond) — those direct implementations win over the
OwnershipFacet routes because the fallback only fires for selectors not
defined on the diamond itself. We still attach OwnershipFacet for
EIP-2535 conformance and so a future diamond shell *without* the inline
methods stays functional.

### 10. AgentRegistry mirrors a snapshot of the manifest. Eventually
consistent. Anyone can call `syncAgent(agentId)` to refresh; an off-chain
indexer should listen to `AgentMetaSynced` for delta updates, plus the
direct events from each agent diamond.

---

## How a v1 happy path looks (no workflow, single-agent use)

```
1. user → UserStateINFT.mint(user, dataHash, sealedKey, encryptedURI)
        → tokenId

2. user → UserStateINFT.authorizeUsage(
            tokenId,
            agentDiamond,
            abi.encode(PermissionScope({
              canRead: true,
              canWrite: true,
              canAppend: true,
              allowedTypes: [],         // wildcard
              allowedWorkflowIds: [0],  // direct (no workflow)
              expiresAt: 0
            }))
          )

3. user → AgentDiamond.userRequest(tokenId, inputPointer, inputType)
        → (requestKey, runId)

4. worker → AgentDiamond.acknowledge(requestKey)
5. (worker does the work off-chain, uploads output to 0G storage)
6. worker → AgentDiamond.complete(
              requestKey,
              outputPointer,
              outputType,
              outputHash,
              labelHash,
              Visibility.ENCRYPTED
            )
            → ledgerItemId

7. (Anyone can read) UserStateLedger.getItemsByRun(tokenId, runId, 0, 100)
```

`secureTransfer` and `cloneToken` need a real (or mock) oracle:

```
8. user1 → UserStateINFT.secureTransfer(user2, tokenId, proofBytes)
   where proofBytes = abi.encode(
            oldDataHash,
            newDataHash,
            newSealedKey,
            user2
          )
   (the MockERC7857Oracle expects exactly this encoding)
```

---

## Deployment order

```
1. AgentRegistry         (admin)
2. MockERC7857Oracle     (admin)            — or skip and pass address(0) initially
3. UserStateINFT         (admin, oracle)
4. UserStateLedger       (UserStateINFT)
5. AgentFactory          (registry, UserStateINFT, UserStateLedger, admin)
6. registry.setFactory(AgentFactory)         — gates registerAgent

Then per-agent:
   factory.createAgent(CreateAgentParams{...})
```

---

## Phase 2 plug-in points

| Phase 2 piece           | Where it plugs in                                        |
|-------------------------|----------------------------------------------------------|
| WorkflowFactory         | Calls each step-agent's `supportsInput()` at create time |
| WorkflowInstance        | Becomes a `trustedCaller` on each agent in its workflow  |
| WorkflowInstance.start  | Calls `AgentExecutionFacet.request(...)` per step        |
| ProtocolTreasury        | Listens to `StepCompleted` / `StepCancelled` for settle  |
| Multi-step ledger writes| `UserStateLedger._deriveWorkflowId` is the only place    |
|                         | that needs changing — it currently returns 0             |
| Workflow-scoped grants  | `LibPermissionScope.allowedWorkflowIds` already supports |
|                         | per-workflow scoping; users will encode workflow-IDs     |
|                         | when granting usage                                      |

The `setTrustedCaller` admin setter on `AgentPermissionFacet` is what lets a
WorkflowInstance call `request()` on agents in its pipeline, without granting
the workflow contract general admin rights.

---

## What I did not do

- **No tests yet.** The compile passes clean (zero warnings under
  `solc 0.8.24` with optimizer 200). I built a runtime smoke test using
  Hardhat but the sandbox can't reach the solc download endpoint — happy to
  ship a `test/` folder once you point at a Hardhat install with offline
  compiler caching, or you can take the contracts as-is into your existing
  build.
- **Real oracle.** `MockERC7857Oracle` accepts the structured payload format
  documented at the top of that file. Wiring a real TEE / ZK verifier
  (e.g. 0G's hosted oracle) means swapping the address via
  `UserStateINFT.setOracle(realOracle)` and ensuring the off-chain prover
  outputs bytes in the same shape (or relaxing the shape in the new oracle).
- **No fee/escrow flow.** Per the Phase 1 scope, there's no native-token
  movement in any of these contracts. Phase 2's WorkflowInstance + Treasury
  is where the money lives.
- **No multi-token-per-wallet.** Spec said "primary iNFT" — enforced.
- **No game-context coupling.** Removed the `LibGameInfoStorage` dependency
  from `LibDiamond.isAuthorized` so this stack is independent of the
  CoreGame work. If you want to combine them in one repo, the diamond
  storage slots don't collide (different keccak namespaces).

---

## Open questions worth a second look before integration

1. **MockERC7857Oracle proof format**: I picked
   `abi.encode(bytes32 oldHash, bytes32 newHash, bytes sealedKey, address recipient)`.
   If 0G's real oracle uses a different shape, the mock should match it so
   integration tests are honest.
2. **`UserStateLedger._deriveWorkflowId` returns 0 in v1.** When workflows
   land, change this to read from a workflow registry indexed by runId, or
   just have the workflow pass its ID explicitly via a new `appendItemFor`
   method.
3. **`AgentDiamond.deployFacet` is owner-only and lets the admin attach
   arbitrary facets** post-deploy. This is by design (matches CoreGameDiamond)
   but means a malicious admin can change the agent's behavior after a user
   has authorized them. Consider freezing this surface once the agent is
   "production" — e.g. a one-shot `freeze()` that disables `deployFacet`.
