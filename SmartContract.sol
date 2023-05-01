// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

// MSHCHNFT is an ERC1155-based NFT contract with a unique minting fee structure and a voting mechanism for Let3 verification.
contract MSHCHNFT is ERC1155, ReentrancyGuard {
    using SafeMath for uint256;

    // State variables with default values
    uint256 private BASE_MINT_FEE;
    uint256 private constant FEE_INCREASE_PERCENTAGE = 3;
    uint256 private constant TRANSFER_FEE = 100 ether;
    uint256 private constant VOTE_THRESHOLD = 1000;
    uint256 public totalSupply;
    uint256 public voteCount;
    uint256 public let3VerificationPercentage;
    mapping(uint256 => string) public tokenTexts;
    // Add the EIP-20 metadata fields to your contract
    string public constant name = unicode"MamaŠČ! NFT";
    string public constant symbol = "TRAKTORA";


    // Mapping to store the votes for Let3
    mapping(address => uint256) public votes;
    mapping(uint256 => bool) public hasVoted;
    address public let3Address;

    // State variables for fees
    uint256 public let3Fees;
    uint256 public creatorFees;
    address public contractCreator;

    // Events
    event Minted(address indexed owner, uint256 indexed nftId);
    event Voted(address indexed voter, address indexed candidate, uint256 indexed nftId);
    event CreatorFeesWithdrawn(address indexed owner, uint256 amount);
    event Let3FeesWithdrawn(address indexed let3Address, uint256 amount);
    event Let3VerificationPercentageChanged(address indexed owner, uint256 newPercentage);
    event Let3VerificationPercentageUpdated(uint256 newPercentage);

    // Constructor: Initializes the contract with default values
    constructor() ERC1155("https://xn--mama-jua71c.hr/metadata.php?tokenId={id}") {
        contractCreator = msg.sender;
        BASE_MINT_FEE = 1 ether;
        let3VerificationPercentage = 90;
    }
   

        // Minting function: Allows users to mint new NFTs by paying the current minting fee
    function mint() external payable nonReentrant {
        uint256 currentFee = currentMintFee();
        require(msg.value >= currentFee, "Error: Insufficient mint fee");

        // Update minting fee and total supply
        totalSupply = totalSupply.add(1);

        // Mint the NFT to the sender
        _mint(msg.sender, totalSupply, 1, abi.encodePacked("https://xn--mama-jua71c.hr/metadata.json"));

        // Update the BASE_MINT_FEE for the next mint
        uint256 updatedBaseMintFee = BASE_MINT_FEE.add(BASE_MINT_FEE.mul(FEE_INCREASE_PERCENTAGE).div(1000));
        BASE_MINT_FEE = updatedBaseMintFee;

        // Distribute fees
        uint256 feeToCreator = currentFee.mul(10).div(100);
        uint256 feeToLet3 = currentFee.sub(feeToCreator);
        creatorFees = creatorFees.add(feeToCreator);
        let3Fees = let3Fees.add(feeToLet3);

        // Return overpaid minting fee amount
        uint256 overpaidAmount = msg.value.sub(currentFee);
        if (overpaidAmount > 0) {
            payable(msg.sender).transfer(overpaidAmount);
        }

        emit Minted(msg.sender, totalSupply);
    }

    // Calculate the current minting fee: Returns the current minting fee based on the total supply and fee increase percentage
    function currentMintFee() public view returns (uint256) {
        uint256 feeMultiplier = (totalSupply.mul(FEE_INCREASE_PERCENTAGE)).div(1000);
        return BASE_MINT_FEE.mul(feeMultiplier.add(100)).div(100);
    }

    // Voting function: Allows users to vote for a Let3 candidate using their NFTs
    function vote(address candidate) external {
        require(candidate != address(0), "Error: Invalid candidate address");
        require(totalSupply >= VOTE_THRESHOLD, "Error: Not enough NFTs minted for voting");
        require(let3Address == address(0), "Error: Voting is closed");

        uint256 nftId = _tokenIdOf(msg.sender);
        require(!hasVoted[nftId], "Error: Already voted with this NFT");

        // Record the vote
        votes[candidate] = votes[candidate].add(1);
        hasVoted[nftId] = true;
        voteCount = voteCount.add(1);

        emit Voted(msg.sender, candidate, nftId);

        // Check if the candidate has reached the required percentage
        if (votes[candidate].mul(100) >= totalSupply.mul(let3VerificationPercentage)) {
            let3Address = candidate;

            // Mint exclusive NFTs
            _mint(msg.sender, totalSupply.add(1), 1, ""); // Congratulatory NFT
            _mint(let3Address, totalSupply.add(2), 1, ""); // Let3 NFT

            // Update total supply
            totalSupply = totalSupply.add(2);
        }
    }
        // Helper function to get the NFT ID of the sender: Returns the NFT ID of the sender that has not been used for voting
    function _tokenIdOf(address sender) private view returns (uint256) {
        for (uint256 i = 1; i <= totalSupply; i++) {
            if (balanceOf(sender, i) > 0 && !hasVoted[i]) {
                return i;
            }
        }
        revert("Error: No eligible NFTs found for voting");
    }

    // Custom safeTransferFrom and safeBatchTransferFrom functions to handle transfer fees
    function customSafeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes memory data) public payable {
        require(msg.value >= TRANSFER_FEE, "Error: Insufficient transfer fee");
        _distributeTransferFees();
        safeTransferFrom(from, to, id, amount, data);
    }

    function customSafeBatchTransferFrom(address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data) public payable {
        require(msg.value >= TRANSFER_FEE, "Error: Insufficient transfer fee");
        _distributeTransferFees();
        safeBatchTransferFrom(from, to, ids, amounts, data);
    }

    // Distribute transfer fees: Splits the transfer fee between the contract creator and Let3
    function _distributeTransferFees() private {
        uint256 feeToCreator = msg.value.mul(10).div(100);
        uint256 feeToLet3 = msg.value.sub(feeToCreator);
        creatorFees = creatorFees.add(feeToCreator);
        let3Fees = let3Fees.add(feeToLet3);
    }

    // Function for the contract creator to withdraw their fees
    function withdrawCreatorFees() external nonReentrant {
        require(msg.sender == contractCreator, "Error: Only contract owner can withdraw fees");
        uint256 amount = creatorFees;
        creatorFees = 0;
        payable(msg.sender).transfer(amount);

        emit CreatorFeesWithdrawn(msg.sender, amount);
    }

    // Function for Let3 to withdraw their fees
    function withdrawLet3Fees() external nonReentrant {
        require(msg.sender == let3Address, "Error: Only Let3 address can withdraw fees");
        require(let3Address != address(0), "Error: Let3 address is not set");
        uint256 amount = let3Fees;
        let3Fees = 0;
        payable(let3Address).transfer(amount);

        emit Let3FeesWithdrawn(let3Address, amount);
    }

}
