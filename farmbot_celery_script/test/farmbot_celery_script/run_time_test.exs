defmodule Farmbot.CeleryScript.RunTimeTest do
  use ExUnit.Case
  alias Farmbot.CeleryScript.RunTime
  import Farmbot.CeleryScript.Utils
  alias Farmbot.CeleryScript.AST

  test "simple rpc_request returns rpc_ok" do
    pid = self()

    io_fun = fn ast ->
      send(pid, ast)
      :ok
    end

    hyper_fun = fn _ -> :ok end
    name = __ENV__.function |> elem(0)

    opts = [
      process_io_layer: io_fun,
      hyper_io_layer: hyper_fun
    ]

    {:ok, farmbot_celery_script} = RunTime.start_link(opts, name)
    label = to_string(name)
    ast = ast(:rpc_request, %{label: label}, [ast(:wait, %{milliseconds: 100})])

    RunTime.rpc_request(farmbot_celery_script, ast, fn result_ast ->
      send(pid, result_ast)
    end)

    assert_receive %AST{kind: :wait, args: %{milliseconds: 100}}
    assert_receive %AST{kind: :rpc_ok, args: %{label: ^label}}
  end

  test "simple rpc_request returns rpc_error" do
    pid = self()

    io_fun = fn ast ->
      send(pid, ast)
      {:error, "reason"}
    end

    hyper_fun = fn _ -> :ok end
    name = __ENV__.function |> elem(0)

    opts = [
      process_io_layer: io_fun,
      hyper_io_layer: hyper_fun
    ]

    {:ok, farmbot_celery_script} = RunTime.start_link(opts, name)
    label = to_string(name)
    ast = ast(:rpc_request, %{label: label}, [ast(:wait, %{milliseconds: 100})])

    RunTime.rpc_request(farmbot_celery_script, ast, fn result_ast ->
      send(pid, result_ast)
    end)

    assert_receive %AST{kind: :wait, args: %{milliseconds: 100}}

    assert_receive %AST{
      kind: :rpc_error,
      args: %{label: ^label},
      body: [%AST{kind: :explanation, args: %{message: "reason"}}]
    }
  end

  test "rpc_request requires `label` argument" do
    assert_raise ArgumentError, fn ->
      # don't need to start a vm here, since this shouldn't actual call the vm.
      RunTime.rpc_request(ast(:rpc_request, %{}, []), fn _ -> :ok end)
    end
  end

  test "emergency_lock and emergency_unlock" do
    pid = self()
    io_fun = fn _ast -> :ok end
    hyper_fun = fn hyper -> send(pid, hyper) end
    name = __ENV__.function |> elem(0)

    opts = [
      process_io_layer: io_fun,
      hyper_io_layer: hyper_fun
    ]

    {:ok, farmbot_celery_script} = RunTime.start_link(opts, name)
    lock_ast = ast(:rpc_request, %{label: name}, [ast(:emergency_lock, %{})])
    RunTime.rpc_request(farmbot_celery_script, lock_ast, io_fun)
    assert_receive :emergency_lock

    unlock_ast =
      ast(:rpc_request, %{label: name}, [ast(:emergency_unlock, %{})])

    RunTime.rpc_request(farmbot_celery_script, unlock_ast, io_fun)
    assert_receive :emergency_unlock
  end

  test "rpc_requests get queued" do
    pid = self()

    io_fun = fn %{kind: :wait, args: %{milliseconds: secs}} ->
      Process.sleep(secs)
      :ok
    end

    hyper_fun = fn _ -> :ok end
    name = __ENV__.function |> elem(0)

    opts = [
      process_io_layer: io_fun,
      hyper_io_layer: hyper_fun
    ]

    {:ok, farmbot_celery_script} = RunTime.start_link(opts, name)

    to = 500
    label1 = "one"
    label2 = "two"

    ast1 =
      ast(:rpc_request, %{label: label1}, [ast(:wait, %{milliseconds: to})])

    ast2 =
      ast(:rpc_request, %{label: label2}, [ast(:wait, %{milliseconds: to})])

    cb = fn %{kind: :rpc_ok} = rpc_ok -> send(pid, rpc_ok) end
    spawn_link(RunTime, :rpc_request, [farmbot_celery_script, ast1, cb])
    spawn_link(RunTime, :rpc_request, [farmbot_celery_script, ast2, cb])

    rpc_ok1 = ast(:rpc_ok, %{label: label1})
    rpc_ok2 = ast(:rpc_ok, %{label: label2})
    refute_received ^rpc_ok1
    refute_received ^rpc_ok2

    assert_receive ^rpc_ok2, to * 2
    assert_receive ^rpc_ok1, to * 2
  end

  test "farm_proc step doesn't crash farmbot_celery_script" do
    pid = self()

    io_fun = fn _ast ->
      raise("oh noes!!")
    end

    hyper_fun = fn _ -> :ok end
    name = __ENV__.function |> elem(0)

    opts = [
      process_io_layer: io_fun,
      hyper_io_layer: hyper_fun
    ]

    {:ok, farmbot_celery_script} = RunTime.start_link(opts, name)
    ast = ast(:rpc_request, %{label: name}, [ast(:wait, %{})])
    RunTime.rpc_request(farmbot_celery_script, ast, fn rpc_err -> send(pid, rpc_err) end)

    assert_receive %AST{
      kind: :rpc_error,
      args: %{label: ^name},
      body: [%AST{kind: :explanation, args: %{message: "oh noes!!"}}]
    }
  end

  test "farmbot_celery_script callbacks with exception won't crash farmbot_celery_script" do
    pid = self()
    io_fun = fn _ast -> :ok end
    hyper_fun = fn _ -> :ok end
    name = __ENV__.function |> elem(0)

    opts = [
      process_io_layer: io_fun,
      hyper_io_layer: hyper_fun
    ]

    {:ok, farmbot_celery_script} = RunTime.start_link(opts, name)
    ast = ast(:rpc_request, %{label: name}, [])

    RunTime.rpc_request(farmbot_celery_script, ast, fn rpc_ok ->
      send(pid, rpc_ok)
      raise("bye!")
    end)

    assert_receive %AST{
      kind: :rpc_ok,
      args: %{label: ^name}
    }
  end

  test "farmbot_celery_script sequence executes callback async" do
    pid = self()

    io_fun = fn ast ->
      send(pid, ast)

      case ast.kind do
        :wait -> :ok
        :send_message -> {:error, "whoops!"}
      end
    end

    hyper_fun = fn _ -> :ok end

    name = __ENV__.function |> elem(0)

    opts = [
      process_io_layer: io_fun,
      hyper_io_layer: hyper_fun
    ]

    {:ok, farmbot_celery_script} = RunTime.start_link(opts, name)
    ok_ast = ast(:sequence, %{id: 100}, [ast(:wait, %{milliseconds: 100})])

    err_ast =
      ast(:sequence, %{id: 101}, [ast(:send_message, %{message: "???"})])

    cb = fn results -> send(pid, results) end
    vm_pid = RunTime.sequence(farmbot_celery_script, ok_ast, 100, cb)
    assert Process.alive?(vm_pid)

    assert_receive %AST{kind: :wait, args: %{milliseconds: 100}}
    assert_receive :ok

    vm_pid = RunTime.sequence(farmbot_celery_script, err_ast, 101, cb)
    assert Process.alive?(vm_pid)

    assert_receive %AST{kind: :send_message, args: %{message: "???"}}
    assert_receive {:error, "whoops!"}
  end
end
