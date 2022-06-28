// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./libraries/SafeERC20.sol";
import "./interfaces/IFON.sol";
import "./interfaces/IWETH.sol";

contract Distributor {
    using SafeERC20 for IERC20;

    address public weth;

    IFON public fon;

    uint public blocksPerYear;
    uint public startBlock;
    uint public endBlock;
    uint public totalWeight;

    uint[11] public tokenPerBlock;
    uint[11] public totalAmountUntilBonus;
    uint[11] public blocksPassed;

    poolInfo[] public rewardPools;

    struct userInfo {
        uint debt;
        uint depositAmount;
    }

    struct poolInfo {
        address token;
        uint rewardRate;
        uint lastBlock;
        uint totalBalance;
        uint weight;
    }

    mapping (address => mapping (uint => userInfo)) public userInfos;

    event NewRewardPool(
        uint indexed idx,
        address rewardPool,
        uint weight
    );
    event NewWeight(
        uint indexed idx,
        uint weight
    );
    event Deposit(
        address indexed account,
        uint indexed idx,
        uint amount
    );
    event Withdrawal(
        address indexed account,
        uint indexed idx,
        uint amount
    );
    event ClaimReward(
        address indexed account,
        uint indexed idx,
        uint amount
    );

    constructor (
        address newFON,
        address newWETH,
        uint newStartBlock,
        uint newBlocksPerYear,
        uint[10] memory distributingAmountsPerYear
    ) {
        fon = IFON(newFON);
        weth = newWETH;
        blocksPerYear = newBlocksPerYear;
        startBlock = newStartBlock;
        endBlock = newStartBlock*10*blocksPerYear;

        for(uint i = 1; i < 11; i++) {
            tokenPerBlock[i - 1] = distributingAmountsPerYear[i - 1] / blocksPerYear;
            totalAmountUntilBonus[i] = totalAmountUntilBonus[i - 1]
                + tokenPerBlock[i - 1]
                * blocksPerYear;
            blocksPassed[i] = blocksPerYear * i;
        }
    }

    function addRewardPool(address token, uint weight) public {
        require(msg.sender == fon.admin(), "FON: admin");
        for (uint i = 0; i < rewardPools.length; i++) {
            update(i);
        }
        rewardPools.push(
            poolInfo(
                token,
                0,
                startBlock > block.number ? startBlock : block.number,
                0,
                weight
            )
        );
        totalWeight += weight;
        emit NewRewardPool(rewardPools.length - 1, token, weight);
    }

    function setWeight(uint idx, uint weight) public {
        require(msg.sender == fon.admin(), "FON: admin");
        for (uint i = 0; i < rewardPools.length; i++) {
            update(i);
        }
        totalWeight = totalWeight - rewardPools[idx].weight + weight;
        rewardPools[idx].weight = weight;

        emit NewWeight(idx, weight);
    }

    function getTotalReward(uint blockNumber) internal view returns (uint) {
        uint period = blockNumber - startBlock;
        uint periodIdx = period / blocksPerYear;
        if(periodIdx > 10) periodIdx = 10;

        return totalAmountUntilBonus[periodIdx]
            + ((period - blocksPassed[periodIdx]) * tokenPerBlock[periodIdx]);
    }

    function rewardPerPeriod(uint fromBlock, uint toBlock) public view returns (uint) {
        return getTotalReward(getBlockInPeriod(toBlock))
            - getTotalReward(getBlockInPeriod(fromBlock));
    }

    function getBlockInPeriod(uint blockNumber) public view returns (uint) {
        blockNumber = blockNumber < startBlock ? startBlock : blockNumber;
        return blockNumber > endBlock ? endBlock : blockNumber;
    }

    function rewardAmount(uint idx, address account) public view returns (uint) {
        poolInfo memory pool = rewardPools[idx];
        userInfo memory user = userInfos[account][idx];

        uint rewardRate = pool.rewardRate;
        if (block.number > pool.lastBlock && pool.totalBalance != 0) {
            rewardRate += rewardPerPeriod(pool.lastBlock, block.number)
                * pool.weight
                * 1e18
                / totalWeight
                / pool.totalBalance;
        }
        return user.depositAmount * rewardRate / 1e18 - user.debt;
    }

    function deposit(uint idx, uint amount) public payable {
        require(idx < rewardPools.length, "FON: pool");

        userInfo storage user = userInfos[msg.sender][idx];
        poolInfo storage pool = rewardPools[idx];

        if (user.depositAmount > 0) {
            claim(idx);
        } else {
            update(idx);
        }

        pool.totalBalance += amount;
        user.depositAmount += amount;
        user.debt = user.depositAmount * pool.rewardRate / 1e18;

        if(pool.token == weth) {
            require(amount == msg.value, "FON: amount");
            IWETH(weth).deposit{value: amount}();
        } else {
            IERC20(pool.token).safeTransferFrom(msg.sender, address(this), amount);
        }

        emit Deposit(msg.sender, idx, amount);
    }

    function withdraw(uint idx, uint amount) public {
        require(idx < rewardPools.length, "FON: pool");

        userInfo storage user = userInfos[msg.sender][idx];
        poolInfo storage pool = rewardPools[idx];

        claim(idx);

        pool.totalBalance -= amount;
        user.depositAmount -= amount;
        user.debt = user.depositAmount * pool.rewardRate / 1e18;

        if(pool.token == weth) {
            IWETH(weth).withdraw(amount);
            payable(msg.sender).transfer(amount);
        } else {
            IERC20(pool.token).safeTransfer(msg.sender, amount);
        }

        emit Withdrawal(msg.sender, idx, amount);
    }

    function update(uint idx) private {
        poolInfo storage pool = rewardPools[idx];

        if (block.number <= pool.lastBlock) {
            return;
        }

        uint currentBlock = block.number >= endBlock ? endBlock : block.number;

        if (pool.totalBalance == 0) {
            pool.lastBlock = currentBlock;
            return;
        }

        uint rewardPerPool = rewardPerPeriod(pool.lastBlock, block.number)
            * pool.weight
            / totalWeight;

        pool.rewardRate += rewardPerPool * 1e18 / pool.totalBalance;
        pool.lastBlock = currentBlock;
    }

    function claim(uint idx) public {
        require(idx < rewardPools.length, "FON: pool");
        userInfo storage user = userInfos[msg.sender][idx];

        update(idx);

        uint reward = user.depositAmount
            * rewardPools[idx].rewardRate
            / 1e18
            - user.debt;

        if(reward > 0) {
            uint rewardFee = reward * fon.stakeFeePercentage() / 1e18;
            user.debt += reward;
            fon.mint(msg.sender, reward - rewardFee);
            fon.mint(fon.stake(), rewardFee);
        }

        emit ClaimReward(msg.sender, idx, reward);
    }

    receive() external payable {
        assert(msg.sender == weth);
    }
}