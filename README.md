# 🧠 0G Workflow Protocol – Contracts

Smart contract system for programmable agent workflows with on-chain execution, modular routing, and automated off-chain execution.

---

## Overview

This repository contains the core contract layer for a workflow execution protocol built around agents.

### Core capabilities

* Register and manage agents
* Compose multi-step workflows
* Execute workflows on-chain
* Route payments via protocol treasury
* Track user state (NFT + ledger)
* Modular execution via Diamond architecture
* Hybrid execution using off-chain workers

---

## Execution Model

```
User
  ↓
WorkflowInstance
  ↓
Agent (via Diamond routing)
  ↓
ProtocolTreasury (payment routing)
  ↓
UserState (NFT / Ledger updates)

          ↓
     Off-chain Worker (continues execution)
```

---

## Tech Stack

* Solidity (>=0.8.20)
* Foundry (Forge, Cast, Anvil)
* Diamond Standard (modular contract routing)
* 0G EVM Testnet

---

## Project Structure (Conceptual)

```
contracts/
├── Agent*                # Agent execution + registry + diamond
├── Workflow*             # Workflow creation + execution
├── ProtocolTreasury.sol  # Payment routing
├── UserState*            # User NFT + ledger tracking
├── interfaces/           # All system interfaces
```

---

## Setup

### Install Foundry

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Build Contracts

```bash
forge build
```

### Run Tests

```bash
forge test
```

---

## ⚠️ Required Pre-Step (Wallet Bootstrap)

Before interacting with contracts, you must generate and fund wallets.

```bash
node script/1_bootstrap_wallets.js
```

### Requirements

* A funded private key

### What it does

* Creates multiple wallets
* Funds them automatically
* Prepares accounts for protocol interaction

If skipped → transactions will fail due to insufficient funds.

---

## Deployment & Execution Flow

**Order is strict. Do not change sequence.**

---

### 1. Deploy Full System

```bash
forge script script/DeployFull.s.sol:DeployFull \
--rpc-url https://evmrpc-testnet.0g.ai/ \
--broadcast \
--legacy \
--via-ir \
-vvvv
```

---

### 2. Create Agents

```bash
forge script script/CreateAgents.s.sol:CreateAgentsInline \
--rpc-url https://evmrpc-testnet.0g.ai/ \
--broadcast \
-vvvv \
--via-ir \
--with-gas-price 3000000000 \
--legacy
```

---

### 3. Set Workflow Factory

```bash
forge script script/SetWorkflowFactory.s.sol \
--rpc-url https://evmrpc-testnet.0g.ai/ \
--broadcast \
-vvvv \
--via-ir \
--with-gas-price 3000000000 \
--legacy
```

---

### 4. Create Workflows

```bash
forge script script/CreateWorkflows.s.sol \
--rpc-url https://evmrpc-testnet.0g.ai/ \
--broadcast \
-vvvv \
--via-ir \
--with-gas-price 3000000000 \
--legacy
```

---

### 5. Start Workflow Execution

```bash
forge script script/StartWorkflow.s.sol:StartWorkflow \
--rpc-url https://evmrpc-testnet.0g.ai/ \
--broadcast \
--legacy \
--via-ir \
-vvvv
```

---

## Off-chain Worker (Required)

After starting a workflow:

```bash
node script/worker.js
```

### Responsibilities

* Monitors workflow state
* Executes pending steps
* Calls agents when required
* Advances workflow execution

Without the worker → workflows will stall.

---

## Minimal End-to-End Flow

```
1. Bootstrap wallets
2. Deploy contracts
3. Register agents
4. Create workflows
5. Start workflow
6. Run worker
7. Observe execution
```

---

## Key Notes

* Gas price is fixed for testnet stability
* `--via-ir` used for optimized compilation
* `--legacy` ensures network compatibility
* Execution is hybrid (on-chain + off-chain)

---

## Common Issues

**Transactions failing**

* Cause: wallets not funded
* Fix: run bootstrap script

**Workflow not progressing**

* Cause: worker not running
* Fix: run `worker.js`

**Deployment errors**

* Cause: incorrect script order
* Fix: follow exact sequence

**RPC issues**

* Cause: wrong endpoint
* Fix: verify RPC URL

---

## What This Enables

* Composable on-chain workflows
* Pay-per-step agent execution
* Modular contract architecture
* Hybrid automation systems
* Scalable execution pipelines

---

## Documentation

[https://book.getfoundry.sh/](https://book.getfoundry.sh/)

---

## Commands Reference

```bash
forge build
forge test
forge fmt
forge snapshot
anvil
cast <subcommand>
```

---

## License

MIT
