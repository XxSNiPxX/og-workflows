// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IProtocolTreasury} from "./interfaces/IProtocolTreasury.sol";

contract ProtocolTreasury is IProtocolTreasury {
    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------

    address public admin;
    address public factory;
    address public feeRecipient;
    uint16 public feeBps;

    mapping(address => bool) internal _registered;
    mapping(bytes32 => Escrow) internal _escrows;

    uint256 public totalFeesCollected;

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------

    event AdminSet(address indexed admin);
    event FactorySet(address indexed factory);
    event FeeRecipientSet(address indexed recipient);
    event FeeBpsSet(uint16 bps);

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------

    error NotAdmin();
    error NotFactory();
    error NotRegisteredWorkflow();
    error ZeroAddress();
    error ZeroAmount();
    error EscrowNotActive();
    error InsufficientBalance();
    error AlreadyRegistered();
    error AlreadyExists();
    error TransferFailed();
    error FeeBpsTooHigh();

    // ---------------------------------------------------------------------
    // Init
    // ---------------------------------------------------------------------

    constructor(address _admin, address _feeRecipient, uint16 _feeBps) {
        if (_admin == address(0)) revert ZeroAddress();
        if (_feeBps > 10_000) revert FeeBpsTooHigh();
        admin = _admin;
        feeRecipient = _feeRecipient;
        feeBps = _feeBps;
        emit AdminSet(_admin);
        emit FeeRecipientSet(_feeRecipient);
        emit FeeBpsSet(_feeBps);
    }

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    modifier onlyFactory() {
        if (msg.sender != factory) revert NotFactory();
        _;
    }

    modifier onlyRegisteredWorkflow() {
        if (!_registered[msg.sender]) revert NotRegisteredWorkflow();
        _;
    }

    // ---------------------------------------------------------------------
    // Admin
    // ---------------------------------------------------------------------

    function setAdmin(address _admin) external onlyAdmin {
        if (_admin == address(0)) revert ZeroAddress();
        admin = _admin;
        emit AdminSet(_admin);
    }

    function setFactory(address _factory) external onlyAdmin {
        if (_factory == address(0)) revert ZeroAddress();
        factory = _factory;
        emit FactorySet(_factory);
    }

    function setFeeRecipient(address _recipient) external onlyAdmin {
        feeRecipient = _recipient;
        emit FeeRecipientSet(_recipient);
    }

    function setFeeBps(uint16 _bps) external onlyAdmin {
        if (_bps > 10_000) revert FeeBpsTooHigh();
        feeBps = _bps;
        emit FeeBpsSet(_bps);
    }

    // ---------------------------------------------------------------------
    // Registration
    // ---------------------------------------------------------------------

    function registerWorkflow(address workflow) external override onlyFactory {
        if (workflow == address(0)) revert ZeroAddress();
        if (_registered[workflow]) revert AlreadyRegistered();
        _registered[workflow] = true;
        emit WorkflowRegistered(workflow);
    }

    function isRegistered(
        address workflow
    ) external view override returns (bool) {
        return _registered[workflow];
    }

    // ---------------------------------------------------------------------
    // Escrow
    // ---------------------------------------------------------------------

    function deposit(
        uint256 runId,
        address payer
    ) external payable override onlyRegisteredWorkflow {
        if (msg.value == 0) revert ZeroAmount();
        bytes32 key = _key(msg.sender, runId);
        Escrow storage e = _escrows[key];
        if (e.status != EscrowStatus.NONE) revert AlreadyExists();

        e.workflow = msg.sender;
        e.payer = payer;
        e.runId = runId;
        e.deposited = msg.value;
        e.status = EscrowStatus.ACTIVE;

        emit Deposited(msg.sender, runId, payer, msg.value);
    }

    function releaseTo(
        uint256 runId,
        address payee,
        uint256 amount
    ) external override onlyRegisteredWorkflow {
        if (payee == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        bytes32 key = _key(msg.sender, runId);
        Escrow storage e = _escrows[key];
        if (e.status != EscrowStatus.ACTIVE) revert EscrowNotActive();
        if (_remaining(e) < amount) revert InsufficientBalance();

        uint256 fee = (feeRecipient == address(0) || feeBps == 0)
            ? 0
            : (amount * feeBps) / 10_000;
        uint256 net = amount - fee;

        e.released += amount;

        if (fee > 0) {
            totalFeesCollected += fee;
            _send(feeRecipient, fee);
        }
        _send(payee, net);

        emit Released(msg.sender, runId, payee, amount, fee);
    }

    function refundTo(
        uint256 runId,
        address recipient,
        uint256 amount
    ) external override onlyRegisteredWorkflow {
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        bytes32 key = _key(msg.sender, runId);
        Escrow storage e = _escrows[key];
        if (e.status != EscrowStatus.ACTIVE) revert EscrowNotActive();
        if (_remaining(e) < amount) revert InsufficientBalance();

        e.refunded += amount;
        _send(recipient, amount);

        emit Refunded(msg.sender, runId, recipient, amount);
    }

    function settle(
        uint256 runId,
        address recipient
    ) external override onlyRegisteredWorkflow {
        bytes32 key = _key(msg.sender, runId);
        Escrow storage e = _escrows[key];
        if (e.status != EscrowStatus.ACTIVE) revert EscrowNotActive();

        uint256 remaining = _remaining(e);
        if (remaining > 0) {
            if (recipient == address(0)) revert ZeroAddress();
            e.refunded += remaining;
            _send(recipient, remaining);
            emit Refunded(msg.sender, runId, recipient, remaining);
        }

        e.status = EscrowStatus.SETTLED;
        emit Settled(msg.sender, runId);
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    function getEscrow(
        address workflow,
        uint256 runId
    ) external view override returns (Escrow memory) {
        return _escrows[_key(workflow, runId)];
    }

    function balanceOf(
        address workflow,
        uint256 runId
    ) external view override returns (uint256) {
        return _remaining(_escrows[_key(workflow, runId)]);
    }

    // ---------------------------------------------------------------------
    // Internal
    // ---------------------------------------------------------------------

    function _key(
        address workflow,
        uint256 runId
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(workflow, runId));
    }

    function _remaining(Escrow storage e) internal view returns (uint256) {
        return e.deposited - e.released - e.refunded;
    }

    // 🔥 FIXED: robust ETH send
    function _send(address to, uint256 amount) internal {
        if (amount == 0) return;

        (bool ok, ) = payable(to).call{value: amount}("");
        if (!ok) {
            // fallback path — cannot fail
            new ForceSend{value: amount}(to);
        }
    }

    receive() external payable {
        revert TransferFailed();
    }
}

// 🔥 helper contract for force send
contract ForceSend {
    constructor(address to) payable {
        selfdestruct(payable(to));
    }
}
