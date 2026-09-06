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

  describe "unavailable_reason/1" do
    test "a service that has never been observed reads as not installed" do
      # Matches status_label/1's existing convention: unobserved is "off", not
      # "unknown" — an operator cannot act on "unknown".
      assert SF.unavailable_reason(nil) == :not_installed
    end

    test "a disabled service is not installed, whatever its last status said" do
      assert SF.unavailable_reason(%{enabled?: false, status: :ready}) == :not_installed
      assert SF.unavailable_reason(%{enabled?: false, status: :unknown}) == :not_installed
    end

    test "an enabled service still coming up is installing" do
      for status <- [:starting, :downloading, :building] do
        assert SF.unavailable_reason(%{enabled?: true, status: status}) == :installing
      end
    end

    test "an enabled, ready service has no reason to report" do
      assert SF.unavailable_reason(%{enabled?: true, status: :ready}) == nil
    end

    test "an enabled service that is up but not ready is failing" do
      for status <- [:error, :unhealthy, :stopped, :unknown] do
        assert SF.unavailable_reason(%{enabled?: true, status: status}) == :failing
      end
    end
  end
end
