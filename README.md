# voting-governance-flow

# 🗳️ Weighted Governance Voting Smart Contract (Flow Blockchain)

A decentralized **weighted governance system** that allows members to vote on proposals with different voting power based on their assigned weights.  
Built entirely in Solidity with **no constructors**, **no imports**, and **no input fields**, this contract provides a minimal yet powerful foundation for decentralized group decision-making.

> 🌐 **Deployed on Flow Blockchain (Testnet)**  
> **Contract Address:** `0x0Ca89b8F97A9E7BfB69Fb559c827C1D384dFc365`

---

## 🧩 Overview

The **Weighted Governance Voting Contract** enables group members to participate in decision-making processes where each vote carries a specific **weight**.  
Members with higher reputation, stake, or contribution can have proportionally greater influence on the outcome.

This contract demonstrates the principles of **decentralized governance**, **on-chain proposal management**, and **weighted voting mechanisms** on the **Flow Blockchain testnet**.

---

## ✨ Key Features

✅ **Weighted Voting Power**  
Each participant has a weight (assigned by the admin) determining how much influence their vote carries.

✅ **Proposal Creation & Voting**  
Anyone can create a proposal, and registered voters can cast votes (“Yes” or “No”) with their assigned weights.

✅ **Transparent Tallying**  
All votes are stored on-chain and tallied transparently for verifiable decision-making.

✅ **Automatic Status Update**  
Proposals automatically switch from *active* to *concluded* after the voting period ends.

✅ **No Constructors or Imports**  
Written in pure Solidity for maximum simplicity and Flow EVM compatibility.

---

## 🛠️ Technical Details

| Parameter | Description |
|------------|--------------|
| **Blockchain** | Flow Blockchain (Testnet) |
| **Contract Address** | `0x0Ca89b8F97A9E7BfB69Fb559c827C1D384dFc365` |
| **Voting Weight Basis** | Manually assigned by the admin |
| **Voting Period** | Fixed (can be set per proposal) |
| **Proposal Lifecycle** | Create → Vote → Conclude |
| **Randomness / External Calls** | None |
| **Security Level** | Educational / Demonstration purpose |

---

## ⚙️ Smart Contract Functions

| Function | Description |
|-----------|--------------|
| `initializeAdmin()` | Sets the admin who manages voter registration and weight assignment. |
| `addVoter(address voter, uint weight)` | Admin function to register voters and assign their vote weight. |
| `createProposal(string memory description, uint duration)` | Creates a new proposal that stays open for `duration` seconds. |
| `vote(uint proposalId, bool support)` | Casts a vote on a proposal. Weighted by the voter’s assigned power. |
| `endProposal(uint proposalId)` | Ends the proposal and determines if it passed or failed. |
| `getProposal(uint proposalId)` | Returns proposal details including votes, description, and status. |
| `getVoterWeight(address voter)` | Returns the assigned weight of a specific voter. |
| `proposalCount()` | Returns the total number of proposals created. |

---

## 🧠 How It Works

1. **Admin Initialization**
   - The contract owner calls:
     ```solidity
     initializeAdmin()
     ```
     This designates the admin who can register voters.

2. **Voter Registration**
   - Admin assigns voter addresses and weights:
     ```solidity
     addVoter(0x1234..., 5)
     addVoter(0x5678..., 2)
     ```

3. **Proposal Creation**
   - Any user can create a proposal:
     ```solidity
     createProposal("Increase community fund allocation", 600)
     ```
     The proposal will remain open for `600 seconds`.

4. **Voting**
   - Registered voters cast their votes:
     ```solidity
     vote(0, true)  // votes in favor
     vote(0, false) // votes against
     ```
     The vote’s impact depends on the voter’s assigned weight.

5. **Proposal Conclusion**
   - After the duration expires, anyone can call:
     ```solidity
     endProposal(0)
     ```
     The contract tallies weighted votes and sets the status (`Passed` / `Failed`).

---

## 🧮 Example Scenario

| Voter | Weight | Vote | Influence |
|-------|---------|------|------------|
| Alice | 5 | Yes | +5 |
| Bob | 2 | No | +2 |
| Carol | 3 | Yes | +3 |

**Result:**  
Yes = 8, No = 2 → ✅ Proposal Passed

---

## 📊 Data Structures

### `struct Proposal`
```solidity
struct Proposal {
    string description;
    uint yesVotes;
    uint noVotes;
    uint deadline;
    bool ended;
    bool passed;
}
