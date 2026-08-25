package ysyx

import chisel3._
import chisel3.util._
import chisel3.experimental.IntParam

import freechips.rocketchip.amba.apb._
import org.chipsalliance.cde.config.Parameters
import freechips.rocketchip.diplomacy._
import freechips.rocketchip.util._

class VGAIO extends Bundle {
  val r = Output(UInt(8.W))
  val g = Output(UInt(8.W))
  val b = Output(UInt(8.W))
  val hsync = Output(Bool())
  val vsync = Output(Bool())
  val valid = Output(Bool())
}

class VGACtrlIO extends Bundle {
  val clock = Input(Clock())
  val reset = Input(Bool())
  val in = Flipped(new APBBundle(APBBundleParameters(addrBits = 32, dataBits = 32)))
  val vga = new VGAIO
}

class VGA_BUFFER_OUT extends Bundle {
  val vga_data = Output(UInt(24.W)) 
  val h_addr = Input(UInt(10.W))   //提供给上层模块的当前扫描像素点坐标
  val v_addr = Input(UInt(10.W))
}

class VGA_BUFFER_IO extends Bundle{
  val in = Flipped(new APBBundle(APBBundleParameters(addrBits = 32, dataBits = 32)))
  val vga_buffer_out = new VGA_BUFFER_OUT
}

class vga_top_apb extends BlackBox {
  val io = IO(new VGACtrlIO)
}

case class Counter_Config(freq: Int, num_counter: Int, total_ms: Seq[Int]) {
    require(freq > 0, "Clock frequency must be positive")
    val countLimit: Map[Int, Int] = (0 until num_counter).map(i => i -> (freq.toLong * total_ms(i) / 1000 - 1).toInt).toMap
    val maxCount = countLimit.values.max
}

class clkgen (clk_freq: Int) extends BlackBox (Map(
  "clk_freq"     -> IntParam(clk_freq)
)) with HasBlackBoxResource{
  val io = IO(new Bundle {
    val clkin = Input(Clock())
    val rst = Input(Bool())
    val clken = Input(Bool())
    val clkout = Output(Clock())
  })
}

class vga_ctrl extends BlackBox with HasBlackBoxResource{
  val io = IO(new Bundle {
    val pclk = Input(Clock())
    val reset = Input(Bool())
    val vga_buffer_out = Flipped(new VGA_BUFFER_OUT)
    val vga = new VGAIO
  })
}

class vga_buffer (address: Seq[AddressSet], PX : Int , PY : Int)extends Module {
  val io = IO(new VGA_BUFFER_IO)

  val nWays = 3
  val wen = io.in.pwrite
  val idx_w = (io.in.paddr - address.head.base.U) >> 2.U // 计算写入的像素索引
  val idx_r = io.vga_buffer_out.h_addr + io.vga_buffer_out.v_addr * PX.U 
  val newTag = io.in.pwdata(23, 0) // 8位数据，表示要写入的像素值

  val buffer  = SyncReadMem(PX * PY, UInt(23.W)) 

  when(wen) {
    // 只写 wayMask 选中的那些 way
    buffer.write(idx_w, newTag)
  }

  when((idx_w === idx_r) & wen){
    io.vga_buffer_out.vga_data := newTag
  }.otherwise{
    io.vga_buffer_out.vga_data := buffer.read(idx_r, true.B)
  }

  io.in.pslverr := 0.U
  io.in.pready := 1.U
  io.in.prdata := 0.U
}

class vgaChisel (address: Seq[AddressSet])extends Module {
  val io = IO(new VGACtrlIO)
/*
  val clkgen_inst = Module(new clkgen(25000000))
    clkgen_inst.io.clkin := clock
    clkgen_inst.io.rst := reset
    clkgen_inst.io.clken := true.B
*/
  val vga_ctrl_inst = Module(new vga_ctrl)
    vga_ctrl_inst.io.pclk := clock
    vga_ctrl_inst.io.reset := reset

  val vga_buffer_inst = Module(new vga_buffer(address, 640, 480))
    vga_buffer_inst.io.in <> io.in
    vga_ctrl_inst.io.vga_buffer_out <> vga_buffer_inst.io.vga_buffer_out
    vga_ctrl_inst.io.vga <> io.vga

}
// LazyModule 不是 Module,是个普通 Scala 对象，是图里的一个顶点，没有 clock、reset，不能放硬件。真正继承 Module 的是 LazyModuleImp。所以天然需要两个对象，而内部类的写法让 Impl 能免费拿到外层的 node 和参数。
// 第二个参数列表带 implicit, 表示这个参数是隐式传递的，调用者可以不显式传入，而是由编译器根据上下文自动推断。
class APBVGA(address: Seq[AddressSet])(implicit p: Parameters) extends LazyModule {
  // APBSlaveNode：diplomacy 的节点对象，外层 Seq 对应该节点可以有多个端口（这里只有一个）。
  // APBSlavePortParameters：描述一个物理端口，端口上可以挂多个从设备（所以内层是 Seq）。
  // node 是一个纯 Scala 对象（协商代理），它在协商结束后会生成 IO.node 里存的是元数据（地址范围、beatBytes、支不支持读写），不是线。等到 elaboration 第二阶段，框架把上下游参数一撮合，才知道 paddr 该是 32 位还是 20 位，这时才真正 IO(...) 出来一组线。
  // 手写 IO 时，位宽对不上、地址译码、协议转换全是自己的事；用 node 时，只写 vga.node := apbXbar.node，框架发现位宽不一致就自动插转换器，地址译码逻辑在 Xbar 里自动生成。
  // executable = true 表示 CPU 可以从这里取指,supportsRead/Write 表示读写都支持, beatBytes = 4 表示数据总线 4 字节 = 32 位。
  val node = APBSlaveNode(Seq(APBSlavePortParameters(
    Seq(APBSlaveParameters(
        address     = address,
      executable    = true,
      supportsRead  = true,
      supportsWrite = true)),
    beatBytes  = 4)))

  //lazy val 表示"第一次被访问时才求值，之后缓存结果"。因为一开始位宽还没被定下来。
  lazy val module = new Impl
  // LazyModuleImp 本质上就是个 Module（MultiIOModule），你在里面写的还是普通 Chisel。定义成具名内部类 Impl 而不是老写法的匿名类 new LazyModuleImp(this) { ... }，主要是为了让 Chisel 能推断出合理的模块名，生成的 Verilog 不至于叫 APBVGA_Impl_1 这种。
  // class Impl —— 定义在 APBVGA 类体内部，是内部类.this指外层的 APBVGA 实例
  class Impl extends LazyModuleImp(this) {
    val (in, _) = node.in(0)
    //node.in 不是"node 中的输入信号"，而是"以本节点为终点的那些连接（边）",node.in：别人连进来的边（本节点是下游/sink）.node.out：本节点连出去的边（本节点是上游/source）
    // APBSlaveNode 是纯 sink，只有 in；APBMasterNode 是纯 source，只有 out；Xbar 这种适配器两边都有。这里 node.in(0) 就是"接进来的第 0 条连接"。
    // edge 参数就是这条边协商出来的结果
    val vga_bundle = IO(new VGAIO)

    val mvga = Module(new vgaChisel(address))
    mvga.io.clock := clock
    mvga.io.reset := reset
    // <> 是 Chisel 的双向批量连接：按字段名把两个 Bundle 对应起来，根据 Input/Output/Flipped 方向自动决定谁驱动谁。
    mvga.io.in <> in
    vga_bundle <> mvga.io.vga
  }
}
