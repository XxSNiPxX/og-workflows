// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IUserStateLedger} from "./interfaces/IUserStateLedger.sol";
import {IUserStateINFT} from "./interfaces/IUserStateINFT.sol";

/// @title UserStateLedger
/// @notice Per-iNFT append-only ledger of typed state items.
contract UserStateLedger is IUserStateLedger {
    struct StoredItem {
        uint256 itemId;
        bytes32 itemType;
        bytes32 pointer;
        bytes32 contentHash;
        bytes32 labelHash;
        uint256 runId;
        uint256 stepIndex;
        Visibility visibility;
        address createdBy;
        uint64 createdAt;
        bool archived;
    }

    IUserStateINFT public immutable inft;

    mapping(uint256 => StoredItem[]) private _items;
    mapping(uint256 => mapping(bytes32 => uint256[])) private _itemsByType;
    mapping(uint256 => mapping(uint256 => uint256[])) private _itemsByRun;
    mapping(address => bool) public registeredWorkflows;

    function registerWorkflow(address workflow) external {
        registeredWorkflows[workflow] = true;
    }

    event ItemAppended(
        uint256 indexed tokenId,
        uint256 indexed itemId,
        bytes32 indexed itemType,
        address createdBy,
        uint256 runId,
        uint256 stepIndex
    );
    event ItemArchived(
        uint256 indexed tokenId,
        uint256 indexed itemId,
        bool archived
    );
    event ItemPointerUpdated(
        uint256 indexed tokenId,
        uint256 indexed itemId,
        bytes32 newPointer,
        bytes32 newContentHash
    );
    event ItemVisibilityUpdated(
        uint256 indexed tokenId,
        uint256 indexed itemId,
        Visibility visibility
    );

    error ZeroAddress();
    error TokenNotFound();
    error UnknownItem();
    error NotTokenOwner();
    error WriterNotAuthorized();
    error PointerImmutable();

    constructor(address _inft) {
        if (_inft == address(0)) revert ZeroAddress();
        inft = IUserStateINFT(_inft);
    }

    function _requireWriterAuthorized(
        uint256 tokenId,
        address workflow,
        bytes32 itemType
    ) internal view {
        address owner = inft.ownerOf(tokenId);

        // Owner always allowed
        if (msg.sender == owner) return;

        // Writer is ALWAYS msg.sender
        address writer = msg.sender;

        // Workflow ID (only if workflow exists)
        uint256 wfId = workflow == address(0) ? 0 : uint256(uint160(workflow));

        // Check writer authorization
        bool writerAllowed = inft.isAuthorizedFor(
            tokenId,
            writer,
            itemType,
            wfId
        );

        // If workflow exists, ALSO require workflow authorization
        if (workflow != address(0)) {
            bool workflowAllowed = inft.isAuthorizedFor(
                tokenId,
                workflow,
                itemType,
                wfId
            );

            if (!workflowAllowed) revert WriterNotAuthorized();
        }

        if (!writerAllowed) revert WriterNotAuthorized();
    }

    function appendItem(
        uint256 tokenId,
        address workflow,
        StateItem calldata item
    ) external override returns (uint256 itemId) {
        address owner;
        try inft.ownerOf(tokenId) returns (address o) {
            owner = o;
        } catch {
            revert TokenNotFound();
        }
        if (owner == address(0)) revert TokenNotFound();

        _requireWriterAuthorized(tokenId, workflow, item.itemType);

        StoredItem[] storage list = _items[tokenId];
        itemId = list.length;

        list.push(
            StoredItem({
                itemId: itemId,
                itemType: item.itemType,
                pointer: item.pointer,
                contentHash: item.contentHash,
                labelHash: item.labelHash,
                runId: item.runId,
                stepIndex: item.stepIndex,
                visibility: item.visibility,
                createdBy: msg.sender,
                createdAt: uint64(block.timestamp),
                archived: false
            })
        );

        _itemsByType[tokenId][item.itemType].push(itemId);
        _itemsByRun[tokenId][item.runId].push(itemId);

        emit ItemAppended(
            tokenId,
            itemId,
            item.itemType,
            msg.sender,
            item.runId,
            item.stepIndex
        );
    }

    function archiveItem(
        uint256 tokenId,
        uint256 itemId,
        bool archived
    ) external {
        if (inft.ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        if (itemId >= _items[tokenId].length) revert UnknownItem();
        _items[tokenId][itemId].archived = archived;
        emit ItemArchived(tokenId, itemId, archived);
    }

    function setItemVisibility(
        uint256 tokenId,
        uint256 itemId,
        Visibility v
    ) external {
        if (inft.ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        if (itemId >= _items[tokenId].length) revert UnknownItem();
        _items[tokenId][itemId].visibility = v;
        emit ItemVisibilityUpdated(tokenId, itemId, v);
    }

    function updateItemPointer(
        uint256 tokenId,
        uint256 itemId,
        bytes32 newPointer,
        bytes32 newContentHash
    ) external {
        if (inft.ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        if (itemId >= _items[tokenId].length) revert UnknownItem();

        StoredItem storage it = _items[tokenId][itemId];
        if (it.contentHash == newContentHash && it.pointer == newPointer) {
            revert PointerImmutable();
        }

        it.pointer = newPointer;
        it.contentHash = newContentHash;
        emit ItemPointerUpdated(tokenId, itemId, newPointer, newContentHash);
    }

    function getItem(
        uint256 tokenId,
        uint256 itemId
    ) external view returns (StoredItem memory) {
        if (itemId >= _items[tokenId].length) revert UnknownItem();
        return _items[tokenId][itemId];
    }

    function getItemsByType(
        uint256 tokenId,
        bytes32 itemType,
        uint256 cursor,
        uint256 limit
    ) external view returns (StoredItem[] memory page, uint256 nextCursor) {
        return
            _paginate(
                _itemsByType[tokenId][itemType],
                _items[tokenId],
                cursor,
                limit
            );
    }

    function getItemsByRun(
        uint256 tokenId,
        uint256 runId,
        uint256 cursor,
        uint256 limit
    ) external view returns (StoredItem[] memory page, uint256 nextCursor) {
        return
            _paginate(
                _itemsByRun[tokenId][runId],
                _items[tokenId],
                cursor,
                limit
            );
    }

    function getAllItems(
        uint256 tokenId,
        uint256 cursor,
        uint256 limit
    ) external view returns (StoredItem[] memory page, uint256 nextCursor) {
        StoredItem[] storage all = _items[tokenId];
        if (cursor >= all.length) return (new StoredItem[](0), all.length);

        uint256 end = cursor + limit;
        if (end > all.length) end = all.length;

        page = new StoredItem[](end - cursor);
        for (uint256 i = cursor; i < end; i++) {
            page[i - cursor] = all[i];
        }
        nextCursor = end;
    }

    function getLatestItemByType(
        uint256 tokenId,
        bytes32 itemType
    ) external view returns (bool found, StoredItem memory item) {
        uint256[] storage idx = _itemsByType[tokenId][itemType];
        for (uint256 i = idx.length; i > 0; i--) {
            StoredItem storage it = _items[tokenId][idx[i - 1]];
            if (!it.archived) return (true, it);
        }
        return (false, item);
    }

    function totalItems(uint256 tokenId) external view returns (uint256) {
        return _items[tokenId].length;
    }

    function _paginate(
        uint256[] storage idx,
        StoredItem[] storage all,
        uint256 cursor,
        uint256 limit
    ) internal view returns (StoredItem[] memory page, uint256 nextCursor) {
        if (cursor >= idx.length) return (new StoredItem[](0), idx.length);

        uint256 end = cursor + limit;
        if (end > idx.length) end = idx.length;

        page = new StoredItem[](end - cursor);
        for (uint256 i = cursor; i < end; i++) {
            page[i - cursor] = all[idx[i]];
        }
        nextCursor = end;
    }
}
