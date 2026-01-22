# DPU_v2 - 深度学习处理单元

## 项目概述

DPU_v2 是一个针对FPGA优化的深度学习处理单元，支持INT8量化卷积神经网络的推理加速。


## 仿真运行

```powershell
xvlog -prj my_project.prj
xelab -debug typical -top tb_cnn_pingpong -snapshot tb_cnn_pingpong_sim
xsim tb_cnn_pingpong_sim -R
```

输出已经放在```sim_output.txt```文件中。