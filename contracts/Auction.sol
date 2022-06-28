// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IERC721.sol";
import "./libraries/SafeERC20.sol";
import "./interfaces/IFON.sol";
import "./interfaces/IFON721.sol";

contract Auction {
    using SafeERC20 for IERC20;

    bytes4 internal constant ON_ERC721_RECEIVED = 0x150b7a02;

    struct AuctionInfo {
        IERC721 nft;
        uint tokenId;
        address beneficiary;
        address highestBidder;
        uint32 endBlock;
        uint112 highestBidAmount;
        bool beneficiaryClaimed;
    }

    IFON public fon;

    mapping(address => mapping(uint => uint)) public bidAmounts;

    AuctionInfo[] public auctionInfos;

    event NewAuction(
        uint indexed auctionId,
        address indexed nftAddress,
        uint indexed tokenId,
        address beneficiary,
        uint endBlock,
        uint minimumBidAmount
    );
    event Bid(
        uint indexed auctionId,
        address indexed account,
        uint amount
    );
    event Claim(
        uint indexed auctionId,
        address indexed account
    );
    event ClaimBeneficiary(uint indexed auctionId);

    constructor (address newFON) {
        fon = IFON(newFON);

        auctionInfos.push(
            AuctionInfo(
                IERC721(address(0)),
                0,
                address(0),
                address(0),
                0,
                0,
                false
            )
        );
    }

    function newAuctionFromMinter(
        uint tokenId,
        uint endBlock,
        uint minimumBidAmount
    ) external {
        require(fon.auctionMinters(msg.sender), "FON: auction minter");
        require(endBlock > block.number, "FON: end block");

        address nftAddress = fon.fon721();
        IFON721 fon721 = IFON721(nftAddress);

        fon721.mintExact(address(this), tokenId);

        auctionInfos.push(
            AuctionInfo(
                IERC721(nftAddress),
                tokenId,
                msg.sender,
                address(0),
                safe32(endBlock),
                safe112(minimumBidAmount),
                false
            )
        );

        emit NewAuction(
            auctionInfos.length - 1,
            nftAddress,
            tokenId,
            msg.sender,
            endBlock,
            minimumBidAmount
        );
    }

    function newAuction(
        address nftAddress,
        address beneficiary,
        uint tokenId,
        uint endBlock,
        uint minimumBidAmount
    ) external {
        require(fon.allowed721(nftAddress), "FON: not allowed");
        require(endBlock > block.number, "FON: end block");

        IERC721 nft = IERC721(nftAddress);
        nft.safeTransferFrom(msg.sender, address(this), tokenId);

        auctionInfos.push(
            AuctionInfo(
                nft,
                tokenId,
                beneficiary,
                address(0),
                safe32(endBlock),
                safe112(minimumBidAmount),
                false
            )
        );

        emit NewAuction(
            auctionInfos.length - 1,
            nftAddress,
            tokenId,
            beneficiary,
            endBlock,
            minimumBidAmount
        );
    }

    function bid(uint auctionId, uint bidAmount) external {
        AuctionInfo storage auctionInfo = auctionInfos[auctionId];
        require(msg.sender != auctionInfo.beneficiary, "FON: beneficiary");
        require(block.number < auctionInfo.endBlock, "FON: over");
        require(auctionInfo.highestBidAmount < bidAmount, "FON: bid amount");

        IERC20(address(fon)).safeTransferFrom(
            msg.sender,
            address(this),
            bidAmount - bidAmounts[msg.sender][auctionId]
        );

        bidAmounts[msg.sender][auctionId] = bidAmount;

        auctionInfo.highestBidAmount = safe112(bidAmount);
        auctionInfo.highestBidder = msg.sender;

        emit Bid(
            auctionId,
            msg.sender,
            bidAmount
        );
    }

    function claim(uint auctionId) external {
        AuctionInfo storage auctionInfo = auctionInfos[auctionId];
        require(msg.sender != auctionInfo.beneficiary, "FON: beneficiary");
        require(bidAmounts[msg.sender][auctionId] > 0, "FON: only once");
        uint bidAmount = bidAmounts[msg.sender][auctionId];
        delete bidAmounts[msg.sender][auctionId];

        if(msg.sender != auctionInfo.highestBidder) {
            IERC20(address(fon)).safeTransfer(msg.sender, bidAmount);
        } else {
            require(block.number >= auctionInfo.endBlock, "FON: not over");

            auctionInfo.nft.safeTransferFrom(
                address(this),
                msg.sender,
                auctionInfo.tokenId
            );
        }

        emit Claim(
            auctionId,
            msg.sender
        );
    }

    function claimBeneficiary(uint auctionId) external {
        AuctionInfo storage auctionInfo = auctionInfos[auctionId];
        require(msg.sender == auctionInfo.beneficiary, "FON: beneficiary");
        require(block.number >= auctionInfo.endBlock, "FON: not over");
        require(!auctionInfo.beneficiaryClaimed, "FON: only once");
        auctionInfo.beneficiaryClaimed = true;

        if(auctionInfo.highestBidder != address(0)) {
            uint feeAmount = fon.auctionFeePercentage() * auctionInfo.highestBidAmount / 1e18;
            uint auctionMinterFeeAmount = fon.auctionMinters(auctionInfo.beneficiary)
            ? fon.auctionMinterFeePercentage() * auctionInfo.highestBidAmount / 1e18
            : 0;

            IERC20 iFON = IERC20(address(fon));
            iFON.safeTransfer(fon.stake(), feeAmount);
            iFON.safeTransfer(
                msg.sender,
                auctionInfo.highestBidAmount - feeAmount - auctionMinterFeeAmount
            );
            if(auctionMinterFeeAmount>0) {
                iFON.safeTransfer(fon.receiver(), auctionMinterFeeAmount);
            }
        } else {
            auctionInfo.nft.safeTransferFrom(
                address(this),
                msg.sender,
                auctionInfo.tokenId
            );
        }

        emit ClaimBeneficiary(auctionId);
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