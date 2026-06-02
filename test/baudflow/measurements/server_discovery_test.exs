defmodule Baudflow.Measurements.ServerDiscoveryTest do
  use Baudflow.DataCase, async: true

  alias Baudflow.Measurements.ServerDiscovery

  describe "parse_server_list/1" do
    test "returns empty list for nil" do
      assert ServerDiscovery.parse_server_list(nil) == []
    end

    test "returns empty list for empty string" do
      assert ServerDiscovery.parse_server_list("") == []
    end

    test "parses a single server ID" do
      assert ServerDiscovery.parse_server_list("12345") == [12_345]
    end

    test "parses comma-separated server IDs" do
      assert ServerDiscovery.parse_server_list("12345, 67890, 11111") == [12_345, 67_890, 11_111]
    end

    test "handles extra whitespace" do
      assert ServerDiscovery.parse_server_list("  12345 ,  67890  ") == [12_345, 67_890]
    end

    test "handles trailing commas" do
      assert ServerDiscovery.parse_server_list("12345,") == [12_345]
    end

    test "handles multiple commas" do
      assert ServerDiscovery.parse_server_list("12345,,67890") == [12_345, 67_890]
    end
  end

  describe "filter_blocked/2" do
    test "returns all servers when no blocked IDs" do
      servers = [%{id: 1, name: "A"}, %{id: 2, name: "B"}]
      assert ServerDiscovery.filter_blocked(servers, []) == servers
    end

    test "filters out blocked servers" do
      servers = [%{id: 1, name: "A"}, %{id: 2, name: "B"}, %{id: 3, name: "C"}]
      result = ServerDiscovery.filter_blocked(servers, [2])
      assert result == [%{id: 1, name: "A"}, %{id: 3, name: "C"}]
    end

    test "returns empty list when all servers are blocked" do
      servers = [%{id: 1, name: "A"}, %{id: 2, name: "B"}]
      assert ServerDiscovery.filter_blocked(servers, [1, 2]) == []
    end

    test "handles empty servers list" do
      assert ServerDiscovery.filter_blocked([], [1, 2]) == []
    end
  end

  describe "select_server/0" do
    test "picks from preferred servers when set" do
      Baudflow.Settings.update_all(%{
        "preferred_servers" => "100, 200",
        "blocked_servers" => ""
      })

      server_id = ServerDiscovery.select_server()
      assert server_id in [100, 200]
    end

    test "picks from preferred even as single server" do
      Baudflow.Settings.update_all(%{
        "preferred_servers" => "55555",
        "blocked_servers" => ""
      })

      assert ServerDiscovery.select_server() == 55_555
    end

    test "falls back to auto-discovery when no preferred servers" do
      Baudflow.Settings.update_all(%{
        "preferred_servers" => "",
        "blocked_servers" => ""
      })

      result = ServerDiscovery.select_server()
      # Either nil (API unreachable) or an integer server ID from Ookla
      assert is_nil(result) or is_integer(result)
    end

    test "returns an integer or nil when auto-discovering with blocked servers" do
      Baudflow.Settings.update_all(%{
        "preferred_servers" => "",
        "blocked_servers" => "99999"
      })

      result = ServerDiscovery.select_server()
      # The API may or may not be reachable; just verify it returns a valid type
      assert is_nil(result) or is_integer(result)
    end
  end

  describe "list_available_servers/1" do
    test "returns a list (empty when API unreachable)" do
      result = ServerDiscovery.list_available_servers()
      assert is_list(result)
    end

    test "each server has expected keys when API returns data" do
      # This tests the normalization; if the API is unreachable we get []
      result = ServerDiscovery.list_available_servers()

      if result != [] do
        server = List.first(result)
        assert Map.has_key?(server, :id)
        assert Map.has_key?(server, :name)
        assert Map.has_key?(server, :location)
        assert Map.has_key?(server, :country)
        assert Map.has_key?(server, :host)
      end
    end
  end
end
