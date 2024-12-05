//===----------------------------------------------------------------------===//
//
// A register allocator simplified from RegAllocFast.cpp
//
//===----------------------------------------------------------------------===//

// Name: Tristan Keith 
// Date: 12/2/2024
// File: RegAllocSimple.cpp

#include "llvm/ADT/Statistic.h"
#include "llvm/CodeGen/MachineFunctionPass.h"
#include "llvm/CodeGen/MachineRegisterInfo.h"
#include "llvm/CodeGen/RegAllocRegistry.h"
#include "llvm/CodeGen/RegisterClassInfo.h"
#include "llvm/CodeGen/TargetInstrInfo.h"
#include "llvm/CodeGen/MachineFrameInfo.h"
#include "llvm/InitializePasses.h"
#include "llvm/Pass.h"

#include "llvm/CodeGen/LiveIntervals.h"
#include "llvm/CodeGen/SlotIndexes.h"

#include <map>
#include <set>
#include <queue>

using namespace llvm;

#define DEBUG_TYPE "regalloc"

STATISTIC(NumStores, "Number of stores added");
STATISTIC(NumLoads , "Number of loads added");

namespace {
  /// This is class where you will implement your register allocator in
  class RegAllocSimple : public MachineFunctionPass {
  public:
    static char ID;
    RegAllocSimple() : MachineFunctionPass(ID) {}

  private:
    /// Some information that might be useful for register allocation
    /// They are initialized in runOnMachineFunction
    MachineFrameInfo *MFI;
    MachineRegisterInfo *MRI;
    const TargetRegisterInfo *TRI;
    const TargetInstrInfo *TII;
    RegisterClassInfo RegClassInfo;

    // TODO: maintain information about live registers
    std::map<Register, 
            std::pair<std::pair<MCRegister, unsigned int>, MachineOperand*>
            > LiveVirtRegs;

    std::set<MCRegister> UsedInInstr;
    std::map<Register, int> SpillMap;

  public:
    StringRef getPassName() const override { return "Simple Register Allocator"; }

    void getAnalysisUsage(AnalysisUsage &AU) const override {
      AU.setPreservesCFG();
      // At -O1/-O2, llc fails to schedule some required passes if this pass
      // does not preserve these anlyses; these are preserved by recomputing
      // them at the end of runOnFunction(), you can safely ignore these
      AU.addRequired<LiveIntervals>();
      AU.addPreserved<LiveIntervals>();
      AU.addRequired<SlotIndexes>();
      AU.addPreserved<SlotIndexes>();
      MachineFunctionPass::getAnalysisUsage(AU);
    }

    /// Ask the Machine IR verifier to check some simple properties
    /// Enabled with the -verify-machineinstrs flag in llc
    MachineFunctionProperties getRequiredProperties() const override {
      return MachineFunctionProperties().set(
          MachineFunctionProperties::Property::NoPHIs);
    }

    MachineFunctionProperties getSetProperties() const override {
      return MachineFunctionProperties().set(
          MachineFunctionProperties::Property::NoVRegs);
    }

    MachineFunctionProperties getClearedProperties() const override {
      return MachineFunctionProperties().set(
        MachineFunctionProperties::Property::IsSSA);
    }

  private:

    // Takes a machine operand and sets it values with the physical register
    void updateMOwithPReg(MachineOperand &MO, Register reg) {

        // check if it is a subregister, if so get the subreg and set it as the 
        // "main register"
        unsigned int subreg = MO.getSubReg();
        if (subreg != 0) {
            reg = TRI->getSubReg(reg, subreg);
            MO.setSubReg(0);
        }

        // Set the machineopernad to the new register 
        MO.setReg(reg);
        // Update values accordingly
        if (MO.isKill()) { MO.setIsKill(false); } 
        if (MO.isDead()) { MO.setIsDead(false); }
        MO.setIsRenamable();
    }

    
    // Returns a stack slot for a register, either allocating a new one or 
    // returning the existing on for a regsiter r
    int allocateStackSlot(Register r) {
        // Already has a stack slot -> return it
        if (SpillMap.find(r) != SpillMap.end()) {
            return SpillMap[r];
        }

        // Allocate a stack slot 

        // Get the register class for the targeted platform
        const TargetRegisterClass* RC = MRI->getRegClass(r);
        // Get the spill_size for the stack slots and the alignment
        unsigned int spill_size = TRI->getSpillSize(*RC);
        Align spill_alignment = TRI->getSpillAlign(*RC);
        // Create the new stack slot with the size and alignment
        int stack_slot = MFI->CreateSpillStackObject(spill_size, spill_alignment);
        // Save for reuse and then return it
        SpillMap[r] = stack_slot;
        return stack_slot;

    }


    // checks if a register is in use
    bool isUsed(MCRegister reg_to_check) {

        // Has it been used in the current instruction 
        for (MCRegister reg : UsedInInstr) {
            if (TRI->regsOverlap(reg, reg_to_check)) {
                return true;
            }
        }


        // Is it currently part of a live register 
        for (auto & [virt_reg, phy_reg_op] : LiveVirtRegs) {
            // Get the physical register with the virtual register including
            // checking for subregisters
            MCRegister p_reg = phy_reg_op.first.first;
            unsigned int subreg = phy_reg_op.first.second;

            // Extract out the subregister if it is a sbregister
            if (subreg) {
                p_reg = TRI->getSubReg(p_reg, subreg);
            }

            if (TRI->regsOverlap(subreg, reg_to_check)) {
                return true;
            }
        }

        // Is not used in the instruction and is not assigned with a live register 
        // so it is not being used
        return false;
    }

    
    // Get the virtual register that is assigned with this physical register
    Register getVirtReg(MCRegister reg) {

        // Iterate over all of the live registers
        for (auto & [virt_reg, phy_reg_op] : LiveVirtRegs) {
            Register v_reg = virt_reg; // The virtual register 
            auto & phy_reg_pair = phy_reg_op.first; // {register, subreg}, operand
            MCRegister p_reg = phy_reg_pair.first; // register ^

            unsigned int subreg = phy_reg_pair.second; // ^
            if (subreg) {
                // Get the subreg if it is the subreg
                p_reg = TRI->getSubReg(p_reg, subreg);
            }      

            // if they overlap this virtual register is assigned with this 
            // phyiscal register -> then return that virtual register
            if (TRI->regsOverlap(p_reg, reg)) {
                return v_reg;
            }
        }

        // The register passed does not match with any live registers
        // so return 0 to be a flag for it
        return 0;
    }

    // Spills the virtual register 
    void spillVirtReg(Register v_reg, MachineBasicBlock::iterator insert_before) {

        // Make sure the register is live to be spilled
        if (LiveVirtRegs.find(v_reg) == LiveVirtRegs.end()) { return; }
       
        // Get the basic block for storing below
        MachineBasicBlock* MBB = insert_before->getParent();

        // {preg, subreg}, operand
        auto & p_reg_pair = LiveVirtRegs[v_reg];
        // Get the slot on the stack to spill too
        int stack_slot = allocateStackSlot(v_reg); 

        // Get the physical register that is is related too, including 
        // get the subreg if it is a subreg
        MCRegister p_reg = p_reg_pair.first.first;
        unsigned int subreg = p_reg_pair.first.second;
        if (subreg) {
            p_reg = TRI->getSubReg(p_reg, subreg);
        }

        // TRC is for the platform independent register storing
        const TargetRegisterClass* regClass = MRI->getRegClass(v_reg);
        TII->storeRegToStackSlot(*MBB, insert_before, p_reg, 
                        p_reg_pair.second->isKill(), stack_slot, regClass, TRI);

        // Increment the number of stores for stats
        NumStores++; 
        // remove this register from live registers as it isn't live its stored
        LiveVirtRegs.erase(v_reg);
    }


    // Finds a register that can be spilled and do so, making a register that is 
    // needed avaiable for use
    MCRegister makeRegAvailable(MachineOperand& MO, llvm::ArrayRef<llvm::MCPhysReg> AllocationOrder) {
        // A collection of possible registers
        std::map<Register, MCRegister> possible_regs;
        // AllocationOrder is a collection of physical registers for a target platform
        // Test every regsiter seeing which are available to spill
        for (MCRegister possible_reg : AllocationOrder) {

            // Make sure to check for subregisters
            MCRegister possible_subreg = possible_reg;
            if (MO.getSubReg()) {
                possible_subreg = TRI->getSubReg(possible_subreg, MO.getSubReg());
            }

            // Get the virtual register associated with the phyiscal registers
            Register v_reg = getVirtReg(possible_subreg);
            // No virtual register so skip
            if (v_reg == 0) {
                continue;
            }

            // Check if it is used in then same instruction
            bool in_same_instr = false;
            for (MCRegister reg : UsedInInstr) {
                if (TRI->regsOverlap(reg, possible_subreg)) {
                    in_same_instr = true;
                    break;
                }
            }
            
            // Passes all the checks so its an available reg
            if (!in_same_instr) {
                // Spills the first possible reg and returns it
                possible_regs[v_reg] = possible_reg;
            } 
        }
        
        // Just spill first reg
        // Spill the register
        spillVirtReg(possible_regs.begin()->first, MO.getParent());
        // Return the register we just spilled
        return possible_regs.begin()->second;
    }


    // Allocate physical register for virtual register operand
    MCRegister allocateOperand(MachineOperand & MO, Register VirtReg, bool is_use) {
        
        // The register has already been assigned a physical register
        if (LiveVirtRegs.find(VirtReg) != LiveVirtRegs.end()) {
            return LiveVirtRegs[VirtReg].first.first;
        }


        // Find an unused register
        bool found = false;

        MCRegister p_reg;
        const TargetRegisterClass * regClass = MRI->getRegClass(VirtReg);
        // collection of physical registers
        auto allocationOrder = RegClassInfo.getOrder(regClass);
        
        // Search through the allocationOrder and look for a register
        for (MCRegister reg : allocationOrder) {
            MCRegister r = reg;
            if (MO.getSubReg()) {
                r = TRI->getSubReg(r, MO.getSubReg());
            }

            // check if this register is in use
            bool is_used = isUsed(r);
            if (!is_used) {
                // If not we can use it
                found = true;
                p_reg = reg;
                break;
            }
        }

        // No regsiter found spill and get
        if (!found) {
            p_reg = makeRegAvailable(MO, allocationOrder);
        }

        // Virt reg not live is spilled on stack so it needs to be loaded
        // isDef doesn't need to be reloaded because it is overwritten later
        if (is_use && !MO.isKill() && !MO.isDead()) {
            // Get the stack slot we are loading form 
            int stack_slot = allocateStackSlot(VirtReg);
            // Used below
            MachineInstr * MI = MO.getParent();
            MachineBasicBlock * MBB = MI->getParent();
            // Load the register from the stack slot 
            TII->loadRegFromStackSlot(*MBB, MI, p_reg, stack_slot, regClass,TRI);
            // Increment for stats
            ++NumLoads;
        }

        // Add it to the live registers
        LiveVirtRegs[VirtReg] = {{p_reg, MO.getSubReg()}, &MO};
        return p_reg;
    }

    // Take care of all register
    void allocateInstruction(MachineInstr &MI) {
        // find and allocate all virtual registers in MI
        UsedInInstr = {};

        // Physical registers
        for (MachineOperand& MO : MI.operands()) {
            if (MO.isReg() && MO.getReg().isPhysical() && MO.getSubReg()) {
                updateMOwithPReg(MO, TRI->getSubReg(MO.getReg(), MO.getSubReg()));
            }
        }

        // Use registers
        for (MachineOperand& MO : MI.operands()) {
            if (MO.isReg() && MO.getReg().isVirtual() && MO.isUse()) {
                MCRegister p_reg = allocateOperand(MO, MO.getReg(), true);
          
                if (MO.getSubReg()) {
                    UsedInInstr.insert(TRI->getSubReg(p_reg, MO.getSubReg()));
                } else {
                    UsedInInstr.insert(p_reg);
                }
                
                updateMOwithPReg(MO, p_reg);
            }
        }


        // Handles register presevation for calls
        for (MachineOperand& MO : MI.operands()) {
            // If it has a register mask it is a function
            if (MO.isRegMask()) {

                std::vector<Register> to_spill;
                // Go over all live registers
                for (auto & [vreg, reg_op_pair] : LiveVirtRegs) {
                    to_spill.push_back(vreg);
                }
                 

                // spill all registers in to_spill
                for (Register & vreg : to_spill) {
                    spillVirtReg(vreg, MO.getParent());
                }
            }
        }
        
        // Def registers
        for (MachineOperand& MO : MI.operands()) {
            if (MO.isReg() && MO.getReg().isVirtual() && MO.isDef()) {

                // Make sure to add any used registers in to usedininstr for 
                // checking
                MCRegister p_reg = allocateOperand(MO, MO.getReg(), false);
                if (MO.getSubReg()) {
                    UsedInInstr.insert(TRI->getSubReg(p_reg, MO.getSubReg()));
                } else {
                    UsedInInstr.insert(p_reg);
                }

                // Update MO with phyiscal register
                updateMOwithPReg(MO, p_reg);
            }
        }
    }


    // Resets everything -> evaluates block, spills all registers at the end
    void allocateBasicBlock(MachineBasicBlock &MBB) {

        LiveVirtRegs.clear();
        SpillMap.clear();

        // Allocate each instruction
        for (MachineInstr& MI : MBB) {
            allocateInstruction(MI);
        }

        // You don't need to spill when its a return block
        if (MBB.isReturnBlock()) return;

        // Spill Live registers
        for (auto [vreg, reg_op_pair] : LiveVirtRegs) {
            // Extract saved information 
            Register v_reg = vreg; // Virtual register
            MCRegister p_reg = reg_op_pair.first.first; // Physical register
            unsigned int subreg = reg_op_pair.first.second; // Subreg idx
            // If it is a subreg elevate
            if (subreg) {
                p_reg = TRI->getSubReg(p_reg, subreg);
            }

            // Actually store the register to the stack 
            MachineOperand& MO = *reg_op_pair.second;
            const TargetRegisterClass* regClass = MRI->getRegClass(v_reg);
            int stack_slot = allocateStackSlot(v_reg);
            TII->storeRegToStackSlot(MBB, MBB.getFirstTerminator(), p_reg, 
                                    MO.isKill(), stack_slot, regClass, TRI);
            ++NumStores;
        }
    }

    bool runOnMachineFunction(MachineFunction &MF) override {
      dbgs() << "simple regalloc running on: " << MF.getName() << "\n";

      // outs() << "simple regalloc not implemented\n";
      // abort();

      // Get some useful information about the target
      MRI = &MF.getRegInfo();
      const TargetSubtargetInfo &STI = MF.getSubtarget();
      TRI = STI.getRegisterInfo();
      TII = STI.getInstrInfo();
      MFI = &MF.getFrameInfo();
      MRI->freezeReservedRegs(MF);
      RegClassInfo.runOnMachineFunction(MF);

      // Allocate each basic block locally
      for (MachineBasicBlock &MBB : MF) {
        allocateBasicBlock(MBB);
      }

      MRI->clearVirtRegs();

      // Recompute the analyses that we marked as preserved above, you can
      // safely ignore this code
      SlotIndexes& SI = getAnalysis<SlotIndexes>();
      SI.releaseMemory();
      SI.runOnMachineFunction(MF);

      LiveIntervals& LI = getAnalysis<LiveIntervals>();
      LI.releaseMemory();
      LI.runOnMachineFunction(MF);

      return true;
    }
  };
}

/// Create the initializer and register the pass
char RegAllocSimple::ID = 0;
FunctionPass *llvm::createSimpleRegisterAllocator() { return new RegAllocSimple(); }
INITIALIZE_PASS(RegAllocSimple, "regallocsimple", "Simple Register Allocator", false, false)
static RegisterRegAlloc simpleRegAlloc("simple", "simple register allocator", createSimpleRegisterAllocator);
