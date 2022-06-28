// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./libraries/SafeERC20.sol";
import "./interfaces/IFON.sol";
import "./interfaces/IFON721.sol";
import "./interfaces/IERC721Receiver.sol";
import "./libraries/ReentrancyGuard.sol";

contract Ticket is IERC721Receiver, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes4 internal constant ON_ERC721_RECEIVED = 0x150b7a02;

    mapping(uint => mapping(uint => uint)) public ticketPrices;
    mapping(uint => bool) public ticketIds;

    IFON public fon;

    event NewTicket(
        uint indexed ticketId,
        uint[] tokenIds,
        uint[] prices
    );
    event TicketBought(
        uint indexed ticketId,
        uint indexed tokenId,
        address indexed buyer,
        uint price
    );

    constructor (address newFON) {
        fon = IFON(newFON);
    }

    function newTicket(
        uint ticketId,
        uint startTokenId,
        uint[] memory prices
    ) external nonReentrant {
        require(fon.minters(msg.sender), "FON: minters");
        require(!ticketIds[ticketId], "FON: ticket id");
        ticketIds[ticketId] = true;

        uint nextTokenId = IFON721(fon.fon721()).nextTokenId();
        require(startTokenId == nextTokenId, "FON: not exact token id");
        uint[] memory tokenIds = new uint[](prices.length);
        for(uint i = 0; i < prices.length; i++) {
            require(prices[i] > 0, "FON: not correct price");
            ticketPrices[ticketId][nextTokenId + i] = prices[i];
            tokenIds[i] = nextTokenId + i;
        }
        IFON721(fon.fon721()).addNextTokenId(prices.length);

        emit NewTicket(
            ticketId,
            tokenIds,
            prices
        );
    }

    function buy(uint ticketId, uint tokenId) external nonReentrant {
        uint price = ticketPrices[ticketId][tokenId];
        require(price > 0, "FON: sold out");
        delete ticketPrices[ticketId][tokenId];

        IERC20(address(fon)).safeTransferFrom(
            msg.sender,
            fon.receiver(),
            price
        );

        IFON721(fon.fon721()).mint(
            msg.sender,
            tokenId
        );

        emit TicketBought(
            ticketId,
            tokenId,
            msg.sender,
            price
        );
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external override returns (bytes4) {
        return ON_ERC721_RECEIVED;
    }
}