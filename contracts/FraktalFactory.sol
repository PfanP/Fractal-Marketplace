pragma solidity >=0.8.0 <0.9.0;
//SPDX-License-Identifier: UNLICENSED

import './FraktalNFT.sol';
import '@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol';
import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./EnumerableMap.sol";

contract FraktalFactory is Ownable, ERC1155Holder, ERC721Holder {
    using EnumerableMap for EnumerableMap.UintToAddressMap;
    address public Fraktalimplementation;
    address public revenueChannelImplementation;
    EnumerableMap.UintToAddressMap private fraktalNFTs;
    uint256[] indexes;
    uint256[] amounts;
    mapping (address => address) public lockedERC721s;
    mapping (address => uint256) public lockedERC721indexes; // careful with overflow
    mapping (address => address) public lockedERC1155s;
    mapping (address => uint256) public lockedERC1155indexes; // careful with overflow

    event Minted(address creator,string urlIpfs,address tokenAddress,uint256 nftId);
    event ERC721Locked(address locker, address tokenAddress, address fraktal, uint256 tokenId);
    event ERC721UnLocked(address owner, uint256 tokenId, address collateralNft, uint256 index);
    event ERC1155Locked(address locker, address tokenAddress, address fraktal, uint256 tokenId);
    event ERC1155UnLocked(address owner, address tokenAddress, address collateralNft, uint256 index);
    event Fraktionalized(address tokenAddress);
    event Defraktionalized(address tokenAddress);
    event RevenuesProtocolUpgraded(address _newAddress);
    event FraktalProtocolUpgraded(address _newAddress);

    // change it to a initializer function > when Clone proxy (if needed)
    constructor(address _implementation, address _revenueChannelImplementation) {
        Fraktalimplementation = _implementation;
        revenueChannelImplementation = _revenueChannelImplementation;
    }

// Admin Functions
//////////////////////////////////
    // finish this.. (could be an array to have history)
    function setFraktalImplementation(address _newAddress) external onlyOwner {
      Fraktalimplementation = _newAddress;
      emit FraktalProtocolUpgraded(_newAddress);
    }
    function setRevenueImplementation(address _newAddress) external onlyOwner {
      revenueChannelImplementation = _newAddress;
      emit RevenuesProtocolUpgraded(_newAddress);
    }

// Users Functions
//////////////////////////////////
    function mint(string memory urlIpfs, uint16 majority) public returns (address _clone) {
      _clone = ClonesUpgradeable.clone(Fraktalimplementation);
      FraktalNFT(_clone).init(_msgSender(), revenueChannelImplementation, urlIpfs, majority);
      uint256 index = fraktalNFTs.length();
      fraktalNFTs.set(index, _clone);
      emit Minted(_msgSender(), urlIpfs, _clone,index);
    }

     /* function fraktionalize(uint256 _tokenId) public {
      // why not call the address directly?
      // this received the nft (was the market) and returns the fraktions
      // fraktionalize can also be done directly with FraktalNFT.. what to do now?
      address tokenAddress = fraktalNFTs.get(_tokenId);
      FraktalNFT(tokenAddress).safeTransferFrom(_msgSender(), address(this),0,1,'');
      FraktalNFT(tokenAddress).fraktionalize(_msgSender(), 1);
      emit Fraktionalized(tokenAddress);
    }
    function defraktionalize(uint256 _tokenId) public {
      // why not calling the address directly
      // defraktionalize should be more flexible (maybe storing the current sub id of fraktions)
      address tokenAddress = fraktalNFTs.get(_tokenId);
      FraktalNFT(tokenAddress).safeTransferFrom(_msgSender(), address(this),1,10000,'');
      FraktalNFT(tokenAddress).defraktionalize(1);
      FraktalNFT(tokenAddress).safeTransferFrom(address(this), _msgSender(), 0, 1, '');
      emit Defraktionalized(tokenAddress);
    }  */

    function importERC721(address _tokenAddress, uint256 _tokenId, uint16 majority) external returns (address _clone) {
      // why dont use interfaces in here?
      // problem in claiming is the URI retrieval
      /* indexes = [0,1]; */
      /* amounts = [1,10000]; */
      string memory uri = ERC721Upgradeable(_tokenAddress).tokenURI(_tokenId);
      ERC721Upgradeable(_tokenAddress).transferFrom(_msgSender(), address(this), _tokenId);
      _clone = this.mint(uri, majority);
      lockedERC721s[_clone] = _tokenAddress;
      lockedERC721indexes[_tokenAddress] = _tokenId;
      /* uint256 index = fraktalNFTs.length() - 1; */
      FraktalNFT(_clone).safeTransferFrom(address(this), _msgSender(), 0, 1, '');
      /* FraktalNFT(fraktalNFTs.get(index)).setApprovalForAll(_msgSender(), true); */
      /* FraktalNFT(fraktalNFTs.get(index)).safeTransferFrom(address(this), _msgSender(), 1, 10000, ''); */
      emit ERC721Locked(_msgSender(), _tokenAddress, _clone, _tokenId);
    }
    function importERC1155(address _tokenAddress, uint256 _tokenId, uint16 majority) external returns (address _clone) {
      // why dont use interfaces in here?
      string memory uri = ERC1155Upgradeable(_tokenAddress).uri(_tokenId);
      ERC1155Upgradeable(_tokenAddress).safeTransferFrom(_msgSender(), address(this), _tokenId, 1, '');
      _clone = this.mint(uri, majority);
      lockedERC1155s[_clone] = _tokenAddress;
      lockedERC1155indexes[_tokenAddress] = _tokenId;
      uint256 index = fraktalNFTs.length() - 1 ;
      FraktalNFT(fraktalNFTs.get(index)).setApprovalForAll(_msgSender(), true);
      FraktalNFT(fraktalNFTs.get(index)).safeTransferFrom(address(this), _msgSender(), 1, 10000, '');
      emit ERC1155Locked(_msgSender(), _tokenAddress, _clone, _tokenId);
    }
    function claimERC721(uint256 _tokenId) external {
      // why dont use interfaces in here? is it possible to have one interface for both schemas?
      // if so, reduce our counters (lockedERC and lockedERCindexes)
      // problem in claiming is the safeTransferFrom vs transferFrom
      address fraktalAddress = fraktalNFTs.get(_tokenId);
      address collateralNft = lockedERC721s[fraktalAddress];
      uint256 index = lockedERC721indexes[collateralNft];
      ERC721Upgradeable(collateralNft).transferFrom(address(this), _msgSender(), index);
      FraktalNFT(fraktalAddress).safeTransferFrom(_msgSender(), address(this),0,1,'');
      fraktalNFTs.set(_tokenId, address(0));
      emit ERC721UnLocked(_msgSender(), _tokenId, collateralNft, index);
    }
    function claimERC1155(uint256 _tokenId) external {
      // why dont use interfaces in here?
      address fraktalAddress = fraktalNFTs.get(_tokenId);
      address collateralNft = lockedERC1155s[fraktalAddress];
      uint256 index = lockedERC1155indexes[collateralNft];
      ERC1155Upgradeable(collateralNft).safeTransferFrom(address(this), _msgSender(), index,1,'');
      FraktalNFT(fraktalAddress).safeTransferFrom(_msgSender(), address(this),0,1,'');
      fraktalNFTs.set(_tokenId, address(0));
      emit ERC1155UnLocked(_msgSender(), fraktalAddress, collateralNft, _tokenId);
    }

// GETTERS
//////////////////////////////////
    function getFraktalAddress(uint256 _tokenId) public view returns(address){
      return address(fraktalNFTs.get(_tokenId));
    }
    function getERC721Collateral(address _tokenId) public view returns(address){
      return(lockedERC721s[_tokenId]);
    }
    function getERC1155Collateral(address _tokenId) public view returns(address){
      return(lockedERC1155s[_tokenId]);
    }
    function getFraktalsLength() public view returns(uint256){
      return(fraktalNFTs.length());
    }
}

// Helpers
//////////////////////////
