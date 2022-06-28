// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IFON.sol";
import "./interfaces/IFON721.sol";
import "./interfaces/IERC721.sol";
import "./FON20.sol";
import "./libraries/SafeMath.sol";
import "./libraries/SafeERC20.sol";

contract FON721Maker {
    using SafeERC20 for IERC20;
    using SafeMath for uint;

    IFON public fon;

    bytes4 internal constant ON_ERC721_RECEIVED = 0x150b7a02;

    struct NFTInfo {
        address nftAddress;
        uint tokenId;
        uint fon721TokenId;
        address owner;
        uint32 endBlock;
        uint112 offeringAmount;
        uint112 totalSupply;
        uint112 offeringPrice;
        address[] holders;
        uint[] holderPercentages;
    }

    mapping(address => mapping(uint => address)) public nftToFON20;
    mapping(address => NFTInfo) public FON20ToNft;

    event NewFON721(
        address indexed nftAddress,
        uint indexed tokenId,
        address indexed fon20,
        address owner,
        uint fon721TokenId,
        uint endBlock,
        uint totalSupply,
        uint offeringAmount,
        uint offeringPrice,
        address[] holders,
        uint[] holderPercentages,
        string fon20Symbol
    );
    event Bought(
        address indexed fon20,
        address indexed account,
        uint fonAmount,
        uint receivingAmount,
        uint leftAmount
    );
    event Claim(address indexed fon20);
    event Exited(
        address indexed nftAddress,
        uint indexed tokenId,
        address indexed fon20,
        uint fon721TokenId,
        address account
    );

    constructor(address newFON) {
        fon = IFON(newFON);
    }

    function newFON721(
        address nftAddress,
        uint tokenId,
        string memory name,
        string memory symbol,
        uint totalSupply,
        uint offeringPercentage,
        uint offeringPrice,
        uint endBlock,
        address[] memory holders,
        uint[] memory holderPercentages
    ) public payable {
        {
            require(fon.allowed721(nftAddress), "FON: not allowed");
            require(endBlock > block.number, "FON: offering block");
            require(msg.value == fon.fon721Fee(), "FON: FON721 fee");
            uint totalHolderPercentage;
            for(uint i = 0; i<holders.length; i++) {
                totalHolderPercentage = totalHolderPercentage.add(holderPercentages[i]);
            }
            require(totalHolderPercentage.add(offeringPercentage) <= 1e18, "FON: holders");
        }
        uint newFON721TokenId;
        address newFON20;
        uint offeringAmount;
        {
            IFON721 iFON721 = IFON721(fon.fon721());
            newFON721TokenId = iFON721.nextTokenId();
            iFON721.addNextTokenId(1);
            newFON20 = address(new FON20(name, symbol, totalSupply));
            offeringAmount = totalSupply.mul(offeringPercentage).div(1e18);
        }
        nftToFON20[nftAddress][tokenId] = newFON20;
        FON20ToNft[newFON20] = NFTInfo(
            nftAddress,
            tokenId,
            newFON721TokenId,
            msg.sender,
            safe32(endBlock),
            safe112(offeringAmount),
            safe112(totalSupply),
            safe112(offeringPrice),
            holders,
            holderPercentages
        );

        IERC721(nftAddress).safeTransferFrom(msg.sender, address(this), tokenId);

        emit NewFON721(
            nftAddress,
            tokenId,
            newFON20,
            msg.sender,
            newFON721TokenId,
            endBlock,
            totalSupply,
            offeringAmount,
            offeringPrice,
            holders,
            holderPercentages,
            FON20(newFON20).symbol()
        );
    }

    function buy(address fon20, uint fonAmount) public {
        NFTInfo storage nftInfo = FON20ToNft[fon20];
        require(block.number < nftInfo.endBlock, "FON: over");

        uint receivingAmount = fonAmount.mul(1e18).div(nftInfo.offeringPrice);
        if(receivingAmount > nftInfo.offeringAmount) {
            fonAmount = uint(nftInfo.offeringAmount).mul(nftInfo.offeringPrice).div(1e18);
            receivingAmount = nftInfo.offeringAmount;
        }
        require(receivingAmount > 0, "FON: sold out");

        nftInfo.offeringAmount = safe112(uint(nftInfo.offeringAmount).sub(receivingAmount));
        IERC20(address(fon)).safeTransferFrom(
            msg.sender,
            nftInfo.owner,
            fonAmount
        );
        IERC20(fon20).safeTransfer(msg.sender, receivingAmount);

        emit Bought(
            fon20,
            msg.sender,
            fonAmount,
            receivingAmount,
            nftInfo.offeringAmount
        );
    }


    function claim(address fon20) public {
        NFTInfo storage nftInfo = FON20ToNft[fon20];
        require(block.number >= nftInfo.endBlock, "FON: not over");

        IERC20 iFON20 = IERC20(fon20);

        for(uint i = 0; i < nftInfo.holders.length; i++) {
            iFON20.safeTransfer(
                nftInfo.holders[i],
                nftInfo.holderPercentages[i].mul(nftInfo.totalSupply).div(1e18)
            );
        }
        iFON20.safeTransfer(nftInfo.owner, iFON20.balanceOf(address(this)));

        IFON721 iFON721 = IFON721(fon.fon721());
        iFON721.mint(nftInfo.owner, nftInfo.fon721TokenId);
        iFON721.setIsShared(nftInfo.fon721TokenId);
        iFON721.setCanTransfer(nftInfo.fon721TokenId, address(0), address(0));

        nftInfo.totalSupply = 0;

        emit Claim(fon20);
    }

    function setCanTransfer(
        address fon20,
        address from,
        address to
    ) public {
        IERC20 iFON20 = IERC20(fon20);
        require(
            iFON20.balanceOf(msg.sender) >=
            iFON20.totalSupply()
            .mul(fon.ownPercentage())
            .div(1e18),
            "FON: own"
        );

        IFON721(fon.fon721()).setCanTransfer(
            FON20ToNft[fon20].fon721TokenId,
            from,
            to
        );
    }

    function exit(address fon20) public {
        IERC20 iFON20 = IERC20(fon20);
        require(
            iFON20.balanceOf(msg.sender) >=
            iFON20.totalSupply()
            .mul(fon.exitPercentage())
            .div(1e18),
            "FON: exit"
        );

        NFTInfo memory nftInfo = FON20ToNft[fon20];
        delete nftToFON20[nftInfo.nftAddress][nftInfo.tokenId];
        delete FON20ToNft[fon20];
        IERC721(fon.fon721()).safeTransferFrom(
            msg.sender,
            address(this),
            nftInfo.fon721TokenId
        );
        IFON721(fon.fon721()).burn(nftInfo.fon721TokenId);
        IERC721(nftInfo.nftAddress).safeTransferFrom(
            address(this),
            msg.sender,
            nftInfo.tokenId
        );

        emit Exited(
            nftInfo.nftAddress,
            nftInfo.tokenId,
            fon20,
            nftInfo.fon721TokenId,
            msg.sender
        );
    }

    function receiveNFTFee() public {
        payable(fon.receiver()).transfer(address(this).balance);
    }

    function safe112(uint amount) internal pure returns (uint112) {
        require(amount < 2**112, "FON: 112");
        return uint112(amount);
    }

    function safe32(uint amount) internal pure returns (uint32) {
        require(amount < 2**32, "FON: 32");
        return uint32(amount);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external returns (bytes4) {
        return ON_ERC721_RECEIVED;
    }
}