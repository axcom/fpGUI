// fpGUI 应用库配置（外部/宿主在此动态指定 Pascal 库名）
// ==========================================================
// libfp_bridge.so 的 start(appLibName) 按参数动态加载 lib<appLibName>.so，
// 本文件是宿主侧的集中指定点：更换 Pascal 应用时只改 APP_LIB_NAME 一处。
// 取值：不带 lib 前缀与 .so 后缀，如 'helloworld' → libhelloworld.so。
export const APP_LIB_NAME: string = 'helloworld';

// 静态命令行参数（空格分隔；支持 -b debug 和 key=value 两种风格）
// Pascal 侧通过 ICmdLineParams 接口消费：cmd.HasOption('b') / cmd.GetOptionValue('key')
export const APP_ARGS: string = '';//'ESC2.INF -style ';

// 动态参数 want key：Ability 从 want.parameters[WANT_PARAM_ARGS] 读取并合并到 APP_ARGS
export const WANT_PARAM_ARGS: string = 'fpArgs';