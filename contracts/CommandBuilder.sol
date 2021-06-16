pragma solidity ^0.8.4;

uint8 constant VARIABLE_LENGTH = 0x80;
uint8 constant INDEX_MASK = 0x7f;
uint8 constant END_OF_ARGS = 0xff;

library CommandBuilder {

    function buildInputs(
        bytes32[] memory staticState,
        bytes[] memory dynamicState,
        bytes4 selector,
        bytes7 indices
    ) internal view returns (bytes memory ret) {
        uint256 count = 0; // Number of bytes in whole ABI encoded message
        uint256 free = 0; // Pointer to first free byte in tail part of message

        // Determine the length of the encoded data
        for (uint256 i = 0; i < 7; i++) {
            uint8 idx = uint8(indices[i]);
            if (idx == END_OF_ARGS) break;

            if (idx & VARIABLE_LENGTH != 0) {
                // Add the size of the value, rounded up to the next word boundary, plus space for pointer and length
                uint256 arglen = dynamicState[idx & INDEX_MASK].length;
                count += ((arglen + 31) / 32) * 32 + 32;
                free += 32;
            } else {
                count += 32;
                free += 32;
            }
        }

        // Encode it
        ret = new bytes(count + 4);
        assembly {
            mstore(add(ret, 32), selector)
        }
        count = 0;
        for (uint256 i = 0; i < 7; i++) {
            uint8 idx = uint8(indices[i]);
            if (idx == END_OF_ARGS) break;

            if (idx & VARIABLE_LENGTH != 0) {
                uint256 arglen = dynamicState[idx & INDEX_MASK].length;

                // Variable length data; put a pointer in the slot and write the data at the end
                assembly {
                    mstore(add(add(ret, 36), count), free)
                }
                memcpy(
                    dynamicState[idx & INDEX_MASK],
                    0,
                    ret,
                    free + 4,
                    arglen
                );
                free += arglen;
                count += 32;
            } else {
                // Fixed length data; write it directly
                bytes32 statevar = staticState[idx & INDEX_MASK];
                assembly {
                    mstore(add(add(ret, 36), count), statevar)
                }
                count += 32;
            }
        }
    }

    function writeOutput(
        bytes32[] memory staticState,
        bytes[] memory dynamicState,
        bytes1 index,
        bytes memory output
    ) internal view {
        uint8 idx = uint8(index);
        if (idx == END_OF_ARGS) return;

        if (idx & VARIABLE_LENGTH != 0) {
            // Check the first field is 0x20 (because we have only a single return value)
            // And copy the rest into state.
            uint256 argptr;
            assembly {
                argptr := mload(add(output, 32))
            }
            require(argptr == 32, "Only one return value permitted");
            bytes memory newstate = new bytes(output.length - 32);
            memcpy(output, 32, newstate, 0, newstate.length);
            dynamicState[idx & INDEX_MASK] = newstate;
        } else {
            // Single word
            require(output.length == 32, "Only one return value permitted");

            bytes32 statevalue;
            assembly {
                statevalue := mload(add(output, 32))
            }
            staticState[idx & INDEX_MASK] = statevalue;
        }
    }

    function memcpy(
        bytes memory src,
        uint256 srcidx,
        bytes memory dest,
        uint256 destidx,
        uint256 len
    ) internal view {
        assembly {
            pop(
                staticcall(
                    gas(),
                    4,
                    add(add(src, 32), srcidx),
                    len,
                    add(add(dest, 32), destidx),
                    len
                )
            )
        }
    }
}
