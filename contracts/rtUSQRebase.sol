// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/swap-router-contracts/contracts/interfaces/ISwapRouter02.sol";
import "./utils/Ownable.sol";
import "./interface/IrtERC20.sol";
import "./utils/SafeMath.sol";
import "./utils/TransferHelper.sol";

contract rtUSQRebase is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public immutable rtUSQ;
    address public admin;

    uint256 public nextTime;
    uint256 public timeInterval = 8 * 60 * 60;
    uint256 public maxRebaseRate = 10;

    error AmountInvalid();

    modifier onlyAdmin() {
        require(msg.sender == admin, "permissions error");
        _;
    }

    constructor(address _admin, address _rtUSQ) Ownable(msg.sender) {
        require(_rtUSQ != address(0), "Cannot be zero address");
        rtUSQ = _rtUSQ;
        admin = _admin;
    }

    function rebase(uint256 rebaseAmt) public onlyAdmin {
        require(nextTime < block.timestamp, "Operating too quickly");
        uint256 totalSupply = IrtERC20(rtUSQ).totalSupply();
        if (rebaseAmt > (totalSupply * maxRebaseRate) / 10000) {
            revert AmountInvalid();
        }
        nextTime = block.timestamp + timeInterval;
        IrtERC20(rtUSQ).rebase(int256(rebaseAmt));
    }

    function withdrawTokensSelf(address token, address to) external onlyOwner {
        require(to != address(0), "Address cannot be zero");
        if (token == address(0)) {
            (bool success, ) = payable(to).call{ value: address(this).balance }("");
            if (!success) {
                revert();
            }
        } else {
            uint256 bal = IERC20(token).balanceOf(address(this));
            IERC20(token).safeTransfer(to, bal);
        }
        emit Withdraw(token, to);
    }

    function setAdmin(address admin_) external onlyOwner {
        require(admin_ != address(0), "Cannot be zero address");
        address prev = admin;
        admin = admin_;
        emit UpdateAdmin(prev, admin_);
    }

    function setMaxRebaseRate(uint256 _max) external onlyOwner {
        uint256 prev = maxRebaseRate;
        maxRebaseRate = _max;
        emit UpdateMaxAmount(prev, _max);
    }

    function setTimeInterval(uint256 _time) external onlyOwner {
        timeInterval = _time;
    }

    event UpdateMaxAmount(uint256 pre, uint256 next);
    event Withdraw(address token, address to);
    event UpdateAdmin(address pre, address next);
}
