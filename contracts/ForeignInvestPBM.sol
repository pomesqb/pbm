// SPDX-License-Identifier: MIT
pragma solidity >=0.8.2 <0.9.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./DigitalTWD.sol";
import "./ForeignInvestLogic.sol";

/**
 * @title ForeignInvestPBM
 * @dev V2.3: Migrated hook from _beforeTokenTransfer (OZ <5) to _update (OZ 5.x).
 */
contract ForeignInvestPBM is ERC1155, Ownable {
    using Counters for Counters.Counter;

    DigitalTWD public immutable underlyingToken;
    ForeignInvestLogic public immutable pbmLogic;

    struct PBMTypeInfo {
        ForeignInvestLogic.PBMType pbmType;
        uint256 settlementTimestamp;
        uint256 faceValue;
        address creator;
    }

    Counters.Counter private _tokenTypeCounter;
    mapping(uint256 => PBMTypeInfo) public pbmTypeRegistry;

    // Custom errors (節省 gas，亦可用 require)
    error PBMTypeNotExist(uint256 id);
    error TransferConditionNotMet(uint256 id);

    event PBMTypeCreated(
        uint256 indexed tokenId,
        ForeignInvestLogic.PBMType pbmType,
        uint256 settlementTimestamp,
        uint256 faceValue
    );
    event PBMMinted(address indexed minter, address indexed to, uint256 id, uint256 amount);
    event PBMRedeemed(address indexed redeemer, address indexed from, uint256 id, uint256 amount);
    event FrozenPBMConverted(address indexed owner, uint256 fromTokenId, uint256 toTokenId, uint256 quantity);

    constructor(
        address _underlyingTokenAddress,
        address _pbmLogicAddress
    ) ERC1155("Foreign Investment PBM V2.3") Ownable(msg.sender) {
        underlyingToken = DigitalTWD(_underlyingTokenAddress);
        pbmLogic = ForeignInvestLogic(_pbmLogicAddress);
    }

    function createPBMType(
        ForeignInvestLogic.PBMType _pbmType,
        uint256 _settlementTimestamp,
        uint256 _faceValue
    ) public returns (uint256) {
        require(_faceValue > 0, "Face value must be positive");

        if (_pbmType != ForeignInvestLogic.PBMType.Frozen) {
            require(_settlementTimestamp > block.timestamp, "Settlement time must be in the future");
        }

        _tokenTypeCounter.increment();
        uint256 newTokenId = _tokenTypeCounter.current();

        pbmTypeRegistry[newTokenId] = PBMTypeInfo({
            pbmType: _pbmType,
            settlementTimestamp: _settlementTimestamp,
            faceValue: _faceValue,
            creator: msg.sender
        });

        emit PBMTypeCreated(newTokenId, _pbmType, _settlementTimestamp, _faceValue);
        return newTokenId;
    }

    function mintPBM(address to, uint256 id, uint256 quantity) public {
        PBMTypeInfo storage pbmInfo = pbmTypeRegistry[id];
        require(pbmInfo.creator != address(0), "PBM type does not exist");

        uint256 totalValue = pbmInfo.faceValue * quantity;
        require(totalValue > 0, "Total value must be positive");

        underlyingToken.transferFrom(msg.sender, address(this), totalValue);
        _mint(to, id, quantity, "");
        emit PBMMinted(msg.sender, to, id, quantity);
    }

    function redeemPBM(address from, uint256 id, uint256 quantity) public {
        PBMTypeInfo storage pbmInfo = pbmTypeRegistry[id];
        require(pbmInfo.creator != address(0), "PBM type does not exist");

        require(
            pbmLogic.unwrapPreCheck(msg.sender, pbmInfo.pbmType, pbmInfo.settlementTimestamp),
            "PBM unlock conditions not met"
        );

        uint256 totalValue = pbmInfo.faceValue * quantity;

        _burn(from, id, quantity);
        underlyingToken.transfer(msg.sender, totalValue);
        emit PBMRedeemed(msg.sender, from, id, quantity);
    }

    function convertFrozenToSettlement(
        uint256 _frozenTokenId,
        uint256 _settlementTokenId,
        uint256 _quantity
    ) public {
        PBMTypeInfo storage frozenInfo = pbmTypeRegistry[_frozenTokenId];
        PBMTypeInfo storage settlementInfo = pbmTypeRegistry[_settlementTokenId];

        require(frozenInfo.pbmType == ForeignInvestLogic.PBMType.Frozen, "Source must be Frozen PBM");
        require(settlementInfo.pbmType == ForeignInvestLogic.PBMType.Settlement, "Target must be Settlement PBM");
        require(frozenInfo.faceValue == settlementInfo.faceValue, "Face values must match for conversion");
        require(pbmLogic.isCustodianBank(msg.sender), "Only custodian banks can perform conversion");

        _burn(msg.sender, _frozenTokenId, _quantity);
        _mint(msg.sender, _settlementTokenId, _quantity, "");

        emit FrozenPBMConverted(msg.sender, _frozenTokenId, _settlementTokenId, _quantity);
    }

    /**
     * OZ 5.x：改為覆寫 _update，而不是 _beforeTokenTransfer
     * operator 以前從參數取得，現在可用 _msgSender()
     */
    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts
    ) internal virtual override {
        // 純轉帳（排除 mint(from=0) 與 burn(to=0)）
        if (from != address(0) && to != address(0)) {
            for (uint256 i = 0; i < ids.length; i++) {
                PBMTypeInfo storage pbmInfo = pbmTypeRegistry[ids[i]];
                if (pbmInfo.creator == address(0)) {
                    revert PBMTypeNotExist(ids[i]);
                }
                if (!pbmLogic.transferPreCheck(from, to, pbmInfo.pbmType)) {
                    revert TransferConditionNotMet(ids[i]);
                }
            }
        }

        // 呼叫父類執行實際狀態更新
        super._update(from, to, ids, amounts);
    }
}