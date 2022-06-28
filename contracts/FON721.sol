// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IFON.sol";
import "./libraries/ERC721Enumerable.sol";

contract FON721 is ERC721Enumerable {
    IFON public fon;

    string public currentBaseURI;

    uint public nextTokenId;

    mapping(uint => bool) public isShared;
    mapping(uint => mapping(address => mapping(address => bool))) public canTransfer;

    event IsShared(
        uint indexed tokenId,
        bool shared
    );
    event CanTransfer(
        uint indexed tokenId,
        address indexed from,
        address indexed to,
        bool approved
    );
    event NextTokenId(uint indexed tokenId);
    event NewBaseURI(string baseURI);

    constructor(
        address newFON,
        string memory name,
        string memory symbol,
        string memory baseURI
    ) ERC721(name, symbol) {
        require(newFON != address(0), "FON: zero address");
        fon = IFON(newFON);

        nextTokenId = 1;
        currentBaseURI = baseURI;
    }

    function mint(address account, uint tokenId) external {
        require(fon.minters(msg.sender), "FON: minter");
        _safeMint(account, tokenId);
    }

    function mintExact(address account, uint tokenId) external {
        require(fon.minters(msg.sender), "FON: minter");
        require(tokenId == nextTokenId, "FON: not exact token id");
        _safeMint(account, nextTokenId);
        nextTokenId++;
    }

    function burn(uint tokenId) external {
        require(msg.sender == fon.fon721maker(), "FON: maker");
        _burn(tokenId);
    }

    function addNextTokenId(uint cnt) external {
        require(fon.minters(msg.sender), "FON: minter");
        nextTokenId += cnt;
        emit NextTokenId(nextTokenId);
    }

    function setBaseURI(string memory newBaseURI) external {
        require(msg.sender == fon.admin(), "FON: admin");
        currentBaseURI = newBaseURI;
        emit NewBaseURI(currentBaseURI);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return currentBaseURI;
    }

    function setIsShared(uint tokenId) external {
        require(msg.sender == fon.fon721maker(), "FON: maker");
        isShared[tokenId] = !isShared[tokenId];

        emit IsShared(
            tokenId,
            isShared[tokenId]
        );
    }

    function setCanTransfer(uint tokenId, address from, address to) external {
        require(msg.sender == fon.fon721maker(), "FON: maker");
        canTransfer[tokenId][from][to] = !canTransfer[tokenId][from][to];

        emit CanTransfer(
            tokenId,
            from,
            to,
            canTransfer[tokenId][from][to]
        );
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal virtual override {
        require(
            from == address(0)
            || !isShared[tokenId]
            || canTransfer[tokenId][address(0)][address(0)]
            || canTransfer[tokenId][from][address(0)]
            || canTransfer[tokenId][from][to],
            "FON: not allowed transfer"
        );
    }
}