package ysyx

import chisel3._
import chisel3.util._

import org.chipsalliance.cde.config.Parameters
import freechips.rocketchip.amba._
import freechips.rocketchip.amba.apb._
import freechips.rocketchip.diplomacy._
import freechips.rocketchip.util._

class APBDelayerIO extends Bundle {
  // val/var是声明关键字， 不用加分号，冒号后是类型(不加类型会自动适配)，等号后是初始值
  // val: 不可变变量，必须初始化，且只能赋值一次，类似于 Java 的 final 变量
  // var: 可变变量，可以多次赋值，类似于 Java 的普通变量
  val clock = Input(Clock())
  val reset = Input(Reset())
  // Flipped 加在根节点上，并不改变成员之间的相对对齐关系——valid/bits 仍然是"对齐"成员，ready 仍然是"翻转"成员。但实际方向已经反了
  val in = Flipped(new APBBundle(APBBundleParameters(addrBits = 32, dataBits = 32)))
  val out = new APBBundle(APBBundleParameters(addrBits = 32, dataBits = 32))
}

class apb_delayer extends BlackBox {
  val io = IO(new APBDelayerIO)
}

case class Delayer_Config(r: Double, s: Int) {
    require(r > 0, s"r 必须为正数，当前为 $r")
    require(isPow2(s), s"s 必须是 2 的幂，当前为 $s")
    
    val log2s: Int = log2Ceil(s)   // s = 2^log2s
    val r_s : Int = (r*s).toInt
}

import chisel3.reflect.DataMirror   // Chisel 3.x 是 chisel3.experimental.DataMirror

class APBDelayerChisel(cfg : Delayer_Config) extends Module {
  val io = IO(new APBDelayerIO)
//  io.out <> io.in
  val counter_s = RegInit(0.U(32.W))
  val counter_m = RegInit(0.U(31.W))
  val counter_m_en = RegInit(false.B)
  val counter_s_en = RegInit(false.B)

  val io_slave_Reg = Reg(Output(chiselTypeOf(io.out)))

  when(io.in.psel & io.in.penable){
    when(io.out.pready){
      counter_s_en := false.B
      when(counter_m_en === false.B){
        counter_m := ((counter_s + 1.U) * cfg.r_s.U) >> cfg.log2s.U
        counter_m_en := true.B
        // 任何 Record（Bundle 是 Record 的子类）都有 elements 成员，类型是 SeqMap[String, Data]，把字段名映射到字段本身
        io.out.elements.foreach { case (name, d) =>
          if (DataMirror.directionOf(d) == ActualDirection.Input) {
            io_slave_Reg.elements(name) := d
          }
        }
      } 
    }.otherwise(
      counter_s_en := true.B
    )
  }

  when(counter_m_en){
    when(counter_m === 0.U){
      counter_m_en := false.B
    }.otherwise(
      counter_m := counter_m - 1.U
    )
  }

  when(counter_s_en){
    counter_s := counter_s + 1.U
  }.otherwise(
    counter_s := 0.U
  )

  io.in.prdata := 0.U
  io.in.pready := false.B
  io.in.pslverr := false.B
  io.out :<= 0.U.asTypeOf(io.out)
  when(counter_m === 0.U){
    io.out :<= io.in
  }.elsewhen(counter_m === 1.U){
    io.in.pready := io_slave_Reg.pready
    io.in.prdata := io_slave_Reg.prdata
    io.in.pslverr := io_slave_Reg.pslverr
  }
}

class APBDelayerWrapper(implicit p: Parameters) extends LazyModule {
  val node = APBIdentityNode()

  lazy val module = new Impl
  class Impl extends LazyModuleImp(this) {
    (node.in zip node.out) foreach { case ((in, edgeIn), (out, edgeOut)) =>
//      val delayer = Module(new apb_delayer)
      val cfg :Delayer_Config = Delayer_Config(1.44 , 8)
      val delayer = Module(new APBDelayerChisel(cfg))
      delayer.io.clock := clock
      delayer.io.reset := reset
      delayer.io.in <> in
      out <> delayer.io.out
    }
  }
}

object APBDelayer {
  def apply()(implicit p: Parameters): APBNode = {
    val apbdelay = LazyModule(new APBDelayerWrapper)
    apbdelay.node
  }
}
