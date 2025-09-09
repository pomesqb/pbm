// SPDX-License-Identifier: MIT
pragma solidity >=0.8.2 <0.9.0;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ForeignInvestLogic
 * @dev V2: Adds timestamp checks for unwrapping.
 */
contract ForeignInvestLogic is Ownable {
    address public tdccAddress;
    mapping(address => bool) public isCustodianBank;

    enum PBMType { Settlement, Repatriation, Frozen }

    event TdccAddressSet(address indexed tdcc);
    event CustodianBankSet(address indexed bank, bool isBank);

    constructor(address initialTdcc) Ownable(msg.sender) {
        setTdccAddress(initialTdcc);
    }

    function setTdccAddress(address _tdcc) public onlyOwner {
        require(_tdcc != address(0), "Invalid TDCC address");
        tdccAddress = _tdcc;
        emit TdccAddressSet(_tdcc);
    }

    function setCustodianBank(address _bank, bool _isBank) public onlyOwner {
        isCustodianBank[_bank] = _isBank;
        emit CustodianBankSet(_bank, _isBank);
    }

    function transferPreCheck(address from, address to, PBMType pbmType) external pure returns (bool) {
        if (pbmType == PBMType.Frozen) {
            return false; // Frozen PBM cannot be transferred
        }
        return true;
    }

    /**
     * @dev V2: Checks if a PBM can be unwrapped, now including a time check.
     * @param _redeemer The address attempting to redeem.
     * @param _pbmType The type of PBM being redeemed.
     * @param _settlementTimestamp The required settlement timestamp for this PBM.
     * @return bool True if conditions are met.
     */
    function unwrapPreCheck(
        address _redeemer,
        PBMType _pbmType,
        uint256 _settlementTimestamp
    ) external view returns (bool) {
        // Time check: a PBM can only be unwrapped on or after its settlement timestamp.
        if (block.timestamp < _settlementTimestamp) {
            return false;
        }

        // Role check
        if (_pbmType == PBMType.Settlement) {
            return _redeemer == tdccAddress;
        }
        if (_pbmType == PBMType.Repatriation) {
            return isCustodianBank[_redeemer];
        }
        if (_pbmType == PBMType.Frozen) {
            return false; // Frozen PBM can never be unwrapped directly.
        }
        return false;
    }
}