# util/

无状态工具集。

## 规则

- 只依赖 Godot 内置类型
- **不依赖**任何业务目录（core / config / generation / climate / compute / rendering / ui / app）
- 无副作用，无全局状态
- 纯函数优先

## 当前内容

- `noise_factory.gd` — 噪声构造工厂

## 禁止放入

- 需要持有状态的类（应放 core/ 或业务目录）
- 需要访问 RenderingDevice 的类（应放 compute/）
- 需要访问场景树的类（应放 app/ 或 ui/）