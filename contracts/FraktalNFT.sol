// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol';
import "./PaymentSplitterUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract FraktalNFT is ERC1155Upgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableMap for EnumerableMap.UintToAddressMap;
    address revenueChannelImplementation;
    bool fraktionalized;
    bool public sold;
    uint256 public fraktionsIndex;
    uint16 public majority;
    mapping (uint256 => bool) public indexUsed;
    mapping(uint256=> mapping(address => uint)) lockedShares;
    mapping(uint256=> mapping(address => uint)) lockedToTotal;
    EnumerableSet.AddressSet private holders;
    EnumerableMap.UintToAddressMap private revenues;

    event LockedSharesForTransfer(address shareOwner, address to, uint numShares);
    event unLockedSharesForTransfer(address shareOwner, address to, uint numShares);
    event ItemSold(address buyer, uint256 indexUsed);
    event NewRevenueAdded(address payer, address revenueChannel, uint256 amount, bool sold);
    event Fraktionalized(address holder, address minter, uint256 index);
    event Defraktionalized(address holder, uint256 index);
    event MajorityValueChanged(uint16 newValue);

    constructor() initializer {}

    function init(address _creator, address _revenueChannelImplementation, string calldata uri, uint16 _majority)
        external
        initializer
    {
        __ERC1155_init(uri);
        _mint(_creator, 0, 1, '');
        fraktionalized = false;
        sold = false;
        majority = _majority;
        revenueChannelImplementation = _revenueChannelImplementation;
        holders.add(_creator);
    }


  // User Functions
  ///////////////////////////
    function fraktionalize(address _to, uint _tokenId) public {
      require(_tokenId != 0, 'Not fraktionalizable');
      require(this.balanceOf(_msgSender(), 0) == 1, 'not owner');
      require(fraktionalized == false, 'fraktionalized');
      require(indexUsed[_tokenId] == false, 'index used');
      fraktionalized = true;
      sold = false;
      fraktionsIndex = _tokenId;
      _mint(_to, _tokenId, 10000, 'fraktions');
      emit Fraktionalized(_msgSender(), _to, _tokenId);
    }
    function defraktionalize() public {
      fraktionalized = false;
      _burn(_msgSender(), fraktionsIndex, 10000);
      emit Defraktionalized(_msgSender(), fraktionsIndex);
    }
    function setMajority(uint16 newValue) public {
      require(this.balanceOf(_msgSender(),0) == 1, 'not owner');
      majority = newValue;
      emit MajorityValueChanged(newValue);
    }
    function soldBurn(address owner, uint256 _tokenId, uint256 bal) public {
      if(_msgSender() != owner){
        require(isApprovedForAll(owner, _msgSender()), 'not approved');
      }
      _burn(owner, _tokenId, bal);
    }
    function lockSharesTransfer(address from, uint numShares, address _to) public {
      if(from != _msgSender()){
          require(isApprovedForAll(from, _msgSender()), 'not approved');
      }
      require(balanceOf(from, fraktionsIndex) - lockedShares[fraktionsIndex][from] >= numShares,"Not balance");
      lockedShares[fraktionsIndex][from] += numShares;
      lockedToTotal[fraktionsIndex][_to] += numShares;
      emit LockedSharesForTransfer(from, _to, numShares);
    }

    function unlockSharesTransfer(address from, address _to) public {
      require(!sold, 'item sold');
      if(from != _msgSender()){
          require(isApprovedForAll(from, _msgSender()), 'not approved');
      }
      uint balance = lockedShares[fraktionsIndex][from];
      lockedShares[fraktionsIndex][from] -= balance;
      lockedToTotal[fraktionsIndex][_to] -= balance;
      emit unLockedSharesForTransfer( from, _to, 0);
    }

    function createRevenuePayment() public payable returns (address _clone){
      cleanUpHolders();
      address[] memory owners = holders.values();
      uint256 listLength = holders.length();
      uint256[] memory fraktions = new uint256[](listLength);
      for (uint i=0; i<listLength; i++){
          fraktions[i]=this.balanceOf(owners[i], fraktionsIndex);
        }
      _clone = ClonesUpgradeable.clone(revenueChannelImplementation);
      address payable revenueContract = payable(_clone);
      PaymentSplitterUpgradeable(revenueContract).init(owners, fraktions);
			uint256 bufferedValue = msg.value;
			AddressUpgradeable.sendValue(revenueContract, bufferedValue);
      uint256 index = revenues.length();
      revenues.set(index, _clone);
      emit NewRevenueAdded(_msgSender(), revenueContract, msg.value, sold);
    }

    function sellItem() public payable {
      require(this.balanceOf(_msgSender(),0) == 1, 'not owner');
      sold = true;
      fraktionalized = false;
      indexUsed[fraktionsIndex] = true;
      emit ItemSold(_msgSender(), fraktionsIndex);
    }

    function cleanUpHolders() internal
    {
      uint256 listLength = holders.length();
      address[] memory remove = new address[](listLength);
      uint16 removeIndex = 0;
      for (uint i=0; i<listLength; i++){
        uint256 bal = this.balanceOf(holders.at(i), fraktionsIndex);
        if(bal < 1){
          remove[removeIndex]= holders.at(i);
          removeIndex++;
        }
      }
      for (uint i=0; i<removeIndex; i++){
        holders.remove(remove[i]);
      }
    }

// Overrided functions
////////////////////////////////
    function _beforeTokenTransfer(address operator, address from, address to, uint256[] memory tokenId,uint256[] memory amount, bytes memory data)
        internal virtual override
    {
        super._beforeTokenTransfer(operator,from, to, tokenId,amount,data);
        if(from != address(0) && to != address(0)){
          if(tokenId[0] == 0){
            if(fraktionalized == true && sold == false){
              require((lockedToTotal[fraktionsIndex][to] > 9999), "not approval");
            }
          }
          else{
            require(sold != true, 'item is sold');
            require(
              (balanceOf(from, tokenId[0]) - lockedShares[fraktionsIndex][from] >= amount[0]),
                "amount wrong"
            );
          }
          holders.add(to);
        }
    }

  // Getters
  ///////////////////////////
  function getRevenue(uint256 index) public view returns(address){
    return revenues.get(index);
  }
  function getFraktions(address who) public view returns(uint){
    return this.balanceOf(who, fraktionsIndex);
  }
  function getLockedShares(uint256 index, address who) public view returns(uint){
    return lockedShares[index][who];
  }
  function getLockedToTotal(uint256 index, address who) public view returns(uint){
    return lockedToTotal[index][who];
  }
  function getStatus() public view returns (bool) {
    return sold;
  }
  function getFraktionsIndex() public view returns (uint256) {
    return fraktionsIndex;
  }
}
