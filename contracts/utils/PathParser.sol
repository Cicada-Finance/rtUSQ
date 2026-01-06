// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library PathParser {
    function getFirstToken(
        bytes memory path
    ) internal pure returns (address token) {
        require(path.length >= 20, "PathParser: PATH_TOO_SHORT");
        assembly {
            let word := mload(add(path, 0x20))
            token := shr(96, word)
        }
    }

    function getLastToken(
        bytes memory path
    ) internal pure returns (address token) {
        uint256 len = path.length;
        require(len >= 20, "PathParser: PATH_TOO_SHORT");
        assembly {
            let ptr := add(add(path, 0x20), sub(len, 20))
            let word := mload(ptr)
            token := shr(96, word)
        }
    }
}
