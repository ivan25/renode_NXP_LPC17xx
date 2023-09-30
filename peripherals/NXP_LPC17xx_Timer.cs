using System;
using Antmicro.Renode.Core;
using Antmicro.Renode.Core.Structure.Registers;
using Antmicro.Renode.Utilities;
using Antmicro.Renode.Logging;
using Antmicro.Renode.Peripherals.Bus;
using Antmicro.Renode.Time;

// TODO 03/12/2022 Cambiare i nomi acronimi nella forma estesa (come richiede Renode per poter integrare una periferica upstream)

namespace Antmicro.Renode.Peripherals.Timers
{
    public class NXP_LPC17xx_Timer : BasicDoubleWordPeripheral, IKnownSize
    {
        public NXP_LPC17xx_Timer(Machine machine, long frequency) : base(machine)
        {
            /* Istanzio i quattro timer */
            timers = new LimitTimer[4];

            for (int i = 0; i < 4; i++)
            {
                timers[i] = new LimitTimer(machine.ClockSource, frequency, this, "LimitTimer", direction: Direction.Ascending, eventEnabled: true);
                timers[i].AutoUpdate = true;
                timers[i].Limit = 200;
            }

            timers[0].LimitReached += () => OnTimerLimitReached(0);
            timers[1].LimitReached += () => OnTimerLimitReached(1);
            timers[2].LimitReached += () => OnTimerLimitReached(2);
            timers[3].LimitReached += () => OnTimerLimitReached(3);

            /* Registri e relativi flag */
            IR = new DoubleWordRegister(this);
            MCR = new DoubleWordRegister(this);
            PR = new DoubleWordRegister(this);
            MR0 = new DoubleWordRegister(this);
            MR1 = new DoubleWordRegister(this);
            MR2 = new DoubleWordRegister(this);
            MR3 = new DoubleWordRegister(this);

            MCRInterruptOnMatches = new IFlagRegisterField[4];
            MCRResetOnMatches = new IFlagRegisterField[4];
            MCRStopOnMatches = new IFlagRegisterField[4];

            for (int i = 0; i < 4; i++)
            {
                MCRInterruptOnMatches[i] = MCR.DefineFlagField(i * 3);
                MCRResetOnMatches[i] = MCR.DefineFlagField(1 + i * 3);
                MCRStopOnMatches[i] = MCR.DefineFlagField(2 + i * 3);
            }
        }

        public override void Reset()
        {
            for (int i = 0; i < 4; i++)
            {
                timers[i].Reset();
            }
        }

        public override void WriteDoubleWord(long offset, uint val)
        {
            LogStatus();

            switch ((Registers)offset)
            {
                /* Timer Control Register */
                case Registers.TCR:
                    if (val == 0)
                    {
                    }
                    else if (val == 1)
                    {
                        /* Scrivendo 0x01 nel TCR si abbilita il timer a contare */
                        timers[0].Enabled = true;
                        timers[1].Enabled = true;
                        timers[2].Enabled = true;
                        timers[3].Enabled = true;
                        this.Log(LogLevel.Debug, "Timer abilitato");
                    }
                    else if (val == 2)
                    {
                        /* Scrivendo 0x02 nel TCR, cioe' 1 nel secondo bit, si resetta il timer */
                        Reset();
                        this.Log(LogLevel.Debug, "Timer resettato");
                    }
                    else
                    {
                        throw new Exception($"Il valore {val} non e' consentito nel registro TCR");
                    }
                    TCR = val;
                    break;
                /* Interrupt Register */
                case Registers.IR:
                    IR.Write(0, val);
                    break;
                /* Prescaler */
                case Registers.PR:
                    timers[0].Divider = (int)val + 1;
                    timers[1].Divider = (int)val + 1;
                    timers[2].Divider = (int)val + 1;
                    timers[3].Divider = (int)val + 1;
                    PR.Write(0, val);
                    this.Log(LogLevel.Debug, "Timer prescaler = {0}", val);
                    break;
                /* Match Registers */
                case Registers.MCR:
                    MCR.Write(0, val);
                    break;
                case Registers.MR0:
                    timers[0].Limit = val;
                    this.Log(LogLevel.Debug, "Timer MR0 = {0}", val);
                    break;
                case Registers.MR1:
                    timers[1].Limit = val;
                    this.Log(LogLevel.Debug, "Timer MR1 = {0}", val);
                    break;
                case Registers.MR2:
                    timers[2].Limit = val;
                    this.Log(LogLevel.Debug, "Timer MR2 = {0}", val);
                    break;
                case Registers.MR3:
                    timers[3].Limit = val;
                    this.Log(LogLevel.Debug, "Timer MR3 = {0}", val);
                    break;
                /* Default */
                default:
                    this.Log(LogLevel.Error, "La scrittura del valore {0} all'offset {1} non e' implementata!", val, offset);
                    this.LogUnhandledWrite(offset, val);
                    throw new Exception($"La scrittura del valore {val} all'offset {offset} non e' implementata!");
            }
        }

        public override uint ReadDoubleWord(long offset)
        {
            LogStatus();

            switch ((Registers)offset)
            {
                /* Timer Counter e Timer Control Register */
                case Registers.TC:
                    return (uint)timers[0].Value;
                case Registers.TCR:
                    return TCR;
                /* Interrupt Register */
                case Registers.IR:
                    return IR.Read();
                /* Prescaler */
                case Registers.PR:
                    return PR.Read();
                /* Match Registers */
                case Registers.MCR:
                    return MCR.Read();
                case Registers.MR0:
                    return (uint)timers[0].Limit;
                case Registers.MR1:
                    return (uint)timers[1].Limit;
                case Registers.MR2:
                    return (uint)timers[2].Limit;
                case Registers.MR3:
                    return (uint)timers[3].Limit;
                /* Default */
                default:
                    this.Log(LogLevel.Error, "Lettura all'offset {0} non consentita", offset);
                    this.LogUnhandledRead(offset);
                    throw new Exception($"La lettura all'offset {offset} non e' implementata!");
            }
        }

        private void OnTimerLimitReached(int i)
        {
            if (MCRResetOnMatches[i].Value)
            {
                timers[0].Reset();
                timers[1].Reset();
                timers[2].Reset();
                timers[3].Reset();
                this.Log(LogLevel.Debug, "Timer match {0} (reset)", i);
            }
            if (MCRStopOnMatches[i].Value)
            {
                timers[0].Enabled = false;
                timers[1].Enabled = false;
                timers[2].Enabled = false;
                timers[3].Enabled = false;
                this.Log(LogLevel.Debug, "Timer match {0} (stop)", i);
            }
        }

        private void LogStatus()
        {
            this.Log(LogLevel.Debug, "--- Timer");
            this.Log(LogLevel.Debug, "TC = {0}, MR0 = {1}", timers[0].Value, timers[0].Limit);
            this.Log(LogLevel.Debug, "PR = {0}, Enabled = {1}", PR.Read(), timers[0].Enabled);
            this.Log(LogLevel.Debug, "---");
        }

        private LimitTimer[] timers;
        private IFlagRegisterField[] MCRInterruptOnMatches;
        private IFlagRegisterField[] MCRResetOnMatches;
        private IFlagRegisterField[] MCRStopOnMatches;

        private DoubleWordRegister IR;
        private uint TCR = 0;
        private DoubleWordRegister PR;
        private DoubleWordRegister MCR;
        private DoubleWordRegister MR0;
        private DoubleWordRegister MR1;
        private DoubleWordRegister MR2;
        private DoubleWordRegister MR3;

        public long Size => 0x74;

        /**
         * Lista di tutti i registri contenuto in un timer
         */
        public enum Registers
        {
            IR = 0x00,
            TCR = 0x04,
            TC = 0x08,
            PR = 0x0C,
            PC = 0x10,
            MCR = 0x14,
            MR0 = 0x18,
            MR1 = 0x1C,
            MR2 = 0x20,
            MR3 = 0x24,
            CCR = 0x28,
            CR0 = 0x2C,
            CR1 = 0x30,
            EMR = 0x3C,
            CTCR = 0x70
        }
    }
}
