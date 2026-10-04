/// 认不出的折叠块写法：装载切段用例与内容校验用例共用这一
/// 份清单——识别口径漂移时两边同时变红，不各自抄一份。
///
/// 每一段都不构成一个合规折叠块，整块 HTML 原样留在普通段里（渲染件照旧丢弃
/// 根级 HTML，因此在 App 里是无声消失）；内容校验必须把每一段都报出来。
const Map<String, String> helpFoldBrokenCases = {
  '缺 `</details>`': '<details>\n<summary>标题</summary>\n正文。\n\n后面一段。\n',
  '缺 `<summary>`': '<details>\n正文。\n</details>\n',
  '`<summary>` 不紧跟 `<details>`':
      '<details>\n\n<summary>标题</summary>\n正文。\n</details>\n',
  '`<summary>` 与 `<details>` 同一行':
      '<details><summary>标题</summary>\n正文。\n</details>\n',
  '`<summary>` 为空': '<details>\n<summary></summary>\n正文。\n</details>\n',
  '`<summary>` 只有空白': '<details>\n<summary>   </summary>\n正文。\n</details>\n',
  '`<summary>` 跨行': '<details>\n<summary>标题\n继续</summary>\n正文。\n</details>\n',
  '嵌套的折叠块':
      '<details>\n'
      '<summary>外</summary>\n'
      '<details>\n<summary>内</summary>\n内正文。\n</details>\n'
      '</details>\n',
  '缩进形式的嵌套':
      '<details>\n'
      '<summary>外</summary>\n'
      '  <details>\n  <summary>内</summary>\n  内正文。\n  </details>\n'
      '</details>\n',
  '引用块形式的嵌套':
      '<details>\n'
      '<summary>外</summary>\n'
      '> <details>\n> <summary>内</summary>\n> 内正文。\n> </details>\n'
      '</details>\n',
  '缩进在列表里的折叠块':
      '- 列表项\n  <details>\n  <summary>标题</summary>\n  正文。\n  </details>\n',
  '引用块里的折叠块': '> <details>\n> <summary>标题</summary>\n> 正文。\n> </details>\n',
  '前面没有空行': '上一段。\n<details>\n<summary>标题</summary>\n正文。\n</details>\n',
  '`</details>` 后面没有空行':
      '<details>\n<summary>标题</summary>\n正文。\n</details>\n紧跟一行。\n',
};
