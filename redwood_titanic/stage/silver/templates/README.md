Chat templates used on silver (copied to /root/stage-ckpt/templates/).

- `olmo3-think-tools.jinja`: for every Olmo 3 / 3.1 Think checkpoint. The stock Think templates
  ignore the `tools` argument and drop `tool` messages, so the model would never see the bash tool or
  its output. This is the Olmo 3.1 32B Instruct template (tools in `<functions>` in the system
  prompt, calls as `<function_calls>`, tool results as the `environment` role, which is how the stock
  Think templates also format functions) with two changes: the default intro is the Think SFT/DPO one
  ("You are a helpful AI assistant."), and the generation prompt opens `<think>` as the stock Think
  templates do. Starts with the `tools | default(none)` line that restart.sh adds to other templates.
