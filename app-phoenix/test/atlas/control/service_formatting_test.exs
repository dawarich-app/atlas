defmodule Atlas.Control.ServiceFormattingTest do
  use ExUnit.Case, async: true

  alias Atlas.Control.ServiceFormatting, as: SF

  describe "status_label/1" do
    test "never-started services read as off, not unknown" do
      assert SF.status_label(%{status: :unknown}) == "off"
      assert SF.status_label(%{status: :unknown, enabled?: false}) == "off"
      assert SF.status_label(nil) == "off"
    end

    test "running states keep their names" do
      assert SF.status_label(%{status: :ready}) == "ready"
      assert SF.status_label(%{status: :downloading}) == "downloading"
      assert SF.status_label(%{status: :stopped}) == "stopped"
      assert SF.status_label(%{status: :error}) == "error"
    end
  end
end
