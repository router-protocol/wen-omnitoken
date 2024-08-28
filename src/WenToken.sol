// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {WenFoundry} from "./WenFoundry.sol";
import {IGateway} from "@routerprotocol/evm-gateway-contracts/contracts/IGateway.sol";

error NotWenFoundry();
error Forbidden();
error LengthUnequal();

/// @title The Wen protocol ERC20 token template.
/// @author strobie <@0xstrobe>
/// @notice Until graduation, the token allowance is restricted to only the WenFoundry, and transfers to certain external entities are not
///         allowed (eg. Uniswap pairs). This makes sure the token is transferable but not tradable before graduation.
contract WenToken is ERC20 {
    struct Metadata {
        WenToken token;
        string name;
        string symbol;
        string description;
        string extended;
        address creator;
        bool isGraduated;
        uint256 mcap;
    }

    struct OutBoundRequest {
        address from;
        uint256 amount;
    }

    bytes32 immutable EMPTY_BYTES = keccak256(abi.encodePacked(""));
    //default: dstGasLimit = ackGasLimit = 500K, ackType = 3, isReadCall = false, asm = ""
    bytes public REQUEST_METADATA =
        hex"000000000007a1200000000000000000000000000007a1200000000000000000000000000000000000000000000000000300";

    string public description;
    string public extended;
    WenFoundry public immutable wenFoundry;
    address public immutable creator;
    IGateway public immutable gateway;

    address[] public holders;
    mapping(address => bool) public isHolder;
    mapping(string => string) public dstTokenContracts;
    mapping(uint256 => OutBoundRequest) public outBoundRequests;

    /// @notice Locked before graduation to restrict trading to WenFoundry
    bool public isUnrestricted = false;

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _supply,
        string memory _description,
        string memory _extended,
        address _wenFoundry,
        address _gateway,
        address _creator
    ) ERC20(_name, _symbol, _decimals) {
        description = _description;
        extended = _extended;
        wenFoundry = WenFoundry(_wenFoundry);
        gateway = IGateway(_gateway);
        creator = _creator;

        _mint(msg.sender, _supply);
        _addHolder(msg.sender);
    }

    modifier onlyCreator() {
        if (msg.sender != creator) revert Forbidden();
        _;
    }

    modifier isGateway() {
        if (msg.sender != address(gateway)) {
            revert Forbidden();
        }
        _;
    }

    function validateIsPregradRestricted(address to) internal view {
        if (!isUnrestricted) {
            bool isPregradRestricted = wenFoundry
                .externalEntities_()
                .isPregradRestricted(address(this), address(to));
            if (isPregradRestricted) revert Forbidden();
        }
    }

    function _addHolder(address holder) private {
        if (!isHolder[holder]) {
            holders.push(holder);
            isHolder[holder] = true;
        }
    }

    function getMetadata() public view returns (Metadata memory) {
        WenFoundry.Pool memory pool = wenFoundry.getPool(this);
        return
            Metadata(
                WenToken(address(this)),
                this.name(),
                this.symbol(),
                description,
                extended,
                creator,
                isGraduated(),
                pool.lastMcapInEth
            );
    }

    function isGraduated() public view returns (bool) {
        WenFoundry.Pool memory pool = wenFoundry.getPool(this);
        return pool.headmaster != address(0);
    }

    function setIsUnrestricted(bool _isUnrestricted) public {
        if (msg.sender != address(wenFoundry)) revert NotWenFoundry();
        isUnrestricted = _isUnrestricted;
    }

    function transfer(
        address to,
        uint256 amount
    ) public override returns (bool) {
        if (!isUnrestricted) {
            bool isPregradRestricted = wenFoundry
                .externalEntities_()
                .isPregradRestricted(address(this), address(to));
            if (isPregradRestricted) revert Forbidden();
        }
        _addHolder(to);
        return super.transfer(to, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        if (!isUnrestricted) {
            bool isPregradRestricted = wenFoundry
                .externalEntities_()
                .isPregradRestricted(address(this), address(to));
            if (isPregradRestricted) revert Forbidden();
        }
        // Pre-approve WenFoundry for improved UX
        if (allowance[from][address(wenFoundry)] != type(uint256).max) {
            allowance[from][address(wenFoundry)] = type(uint256).max;
        }
        _addHolder(to);
        return super.transferFrom(from, to, amount);
    }

    function approve(
        address spender,
        uint256 amount
    ) public override returns (bool) {
        if (!isUnrestricted) revert Forbidden();

        return super.approve(spender, amount);
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public override {
        if (!isUnrestricted) revert Forbidden();

        super.permit(owner, spender, value, deadline, v, r, s);
    }

    /// Get all addresses who have ever held the token with their balances
    /// @return The holders and their balances
    /// @notice Some holders may have a zero balance
    function getHoldersWithBalance(
        uint256 offset,
        uint256 limit
    ) public view returns (address[] memory, uint256[] memory) {
        uint256 length = holders.length;
        if (offset >= length) {
            return (new address[](0), new uint256[](0));
        }

        uint256 end = offset + limit;
        if (end > length) {
            end = length;
        }

        address[] memory resultAddresses = new address[](end - offset);
        uint256[] memory resultBalances = new uint256[](end - offset);

        for (uint256 i = offset; i < end; i++) {
            address holder = holders[i];
            resultAddresses[i - offset] = holder;
            resultBalances[i - offset] = balanceOf[holder];
        }

        return (resultAddresses, resultBalances);
    }

    /// Get all addresses who have ever held the token
    /// @return The holders
    /// @notice Some holders may have a zero balance
    function getHolders(
        uint256 offset,
        uint256 limit
    ) public view returns (address[] memory) {
        uint256 length = holders.length;
        if (offset >= length) {
            return new address[](0);
        }

        uint256 end = offset + limit;
        if (end > length) {
            end = length;
        }

        address[] memory result = new address[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            result[i - offset] = holders[i];
        }

        return result;
    }

    /// Get the number of all addresses who have ever held the token
    /// @return The number of holders
    /// @notice Some holders may have a zero balance
    function getHoldersLength() public view returns (uint256) {
        return holders.length;
    }

    function setDappMetadata(
        string memory feePayer
    ) external payable onlyCreator {
        gateway.setDappMetadata{value: msg.value}(feePayer);
    }

    function updateRequestMetadata(
        uint64 destGasLimit,
        uint64 destGasPrice,
        uint64 ackGasLimit,
        uint64 ackGasPrice,
        uint128 relayerFees,
        uint8 ackType,
        bool isReadCall,
        string memory asmAddress
    ) public onlyCreator {
        REQUEST_METADATA = abi.encodePacked(
            destGasLimit,
            destGasPrice,
            ackGasLimit,
            ackGasPrice,
            relayerFees,
            ackType,
            isReadCall,
            asmAddress
        );
    }

    function transferCrossChain(
        address to, // cross-chain transfer accross evm only
        string memory dstChainId,
        uint256 amount
    ) public payable {
        validateIsPregradRestricted(to);
        string memory dstTokenContract = dstTokenContracts[dstChainId];
        // dst contract not mapped
        if (keccak256(abi.encodePacked(dstTokenContract)) == EMPTY_BYTES) {
            revert Forbidden();
        }
        super._burn(msg.sender, amount);
        bytes memory payload = abi.encode(to, amount);
        bytes memory requestPacket = abi.encode(dstTokenContract, payload);
        uint256 eventNonce = gateway.iSend{value: msg.value}(
            1,
            0,
            "",
            dstChainId,
            REQUEST_METADATA,
            requestPacket
        );
        outBoundRequests[eventNonce] = OutBoundRequest(msg.sender, amount);
    }

    function mapDstWenTokenContracts(
        string[] memory dstChainIds,
        string[] memory dstContracts
    ) public onlyCreator {
        if (dstChainIds.length != dstContracts.length) {
            revert LengthUnequal();
        }
        for (uint256 idx = 0; idx < dstChainIds.length; idx++) {
            dstTokenContracts[dstChainIds[idx]] = dstContracts[idx];
        }
    }

    function iReceive(
        string memory requestSender,
        bytes memory packet,
        string memory srcChainId
    ) external isGateway {
        if (
            keccak256(abi.encodePacked(requestSender)) !=
            keccak256(abi.encodePacked(dstTokenContracts[srcChainId]))
        ) {
            revert Forbidden();
        }
        (address to, uint256 amount) = abi.decode(packet, (address, uint256));
        validateIsPregradRestricted(to);
        super._mint(to, amount);
        _addHolder(to);
    }

    function iAck(
        uint256 eventIdentifier,
        bool execFlag,
        bytes memory
    ) external isGateway {
        if (execFlag) {
            delete outBoundRequests[eventIdentifier];
            return;
        }
        OutBoundRequest memory oreq = outBoundRequests[eventIdentifier];
        super._mint(oreq.from, oreq.amount);
        _addHolder(oreq.from);
        delete outBoundRequests[eventIdentifier];
    }
}
