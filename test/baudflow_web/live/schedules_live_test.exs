defmodule BaudflowWeb.SchedulesLiveTest do
  use BaudflowWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Baudflow.Scheduling

  describe "index" do
    test "lists schedules in a table with a New button", %{conn: conn} do
      {:ok, schedule} = Scheduling.create(%{name: "Hourly", cron: "0 * * * *"})
      {:ok, lv, html} = live(conn, ~p"/schedules")

      assert html =~ "Schedules"
      assert has_element?(lv, "#schedules-table")
      assert has_element?(lv, "#schedule-row-#{schedule.id}")
      assert html =~ "Hourly"
      assert has_element?(lv, "a[href='/schedules/new']")
    end

    test "shows the empty state when there are no schedules", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/schedules")
      assert html =~ "No schedules yet"
    end
  end

  describe "new" do
    test "renders the new-schedule form with the threshold policy select", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/schedules/new")
      assert html =~ "New schedule"
      assert has_element?(lv, "#schedule-form")
      assert has_element?(lv, "select[name='schedule[threshold_policy]']")
    end

    test "creates a schedule and returns to the table", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/schedules/new")

      lv
      |> element("#schedule-form")
      |> render_submit(%{schedule: %{name: "Hourly", cron: "0 * * * *"}})

      assert_patch(lv, ~p"/schedules")
      assert [%{name: "Hourly", cron: "0 * * * *"}] = Scheduling.list_schedules()
      assert render(lv) =~ "Schedule created"
    end

    test "rejects an unparseable cron without creating a schedule", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/schedules/new")

      lv
      |> element("#schedule-form")
      |> render_submit(%{schedule: %{name: "Bad", cron: "not a cron"}})

      assert Scheduling.list_schedules() == []

      html = render(lv)
      assert html =~ "is not a valid cron expression"
      assert html =~ "Could not save"
    end
  end

  describe "edit" do
    test "renders the edit form prefilled", %{conn: conn} do
      {:ok, schedule} = Scheduling.create(%{name: "Hourly", cron: "0 * * * *"})
      {:ok, lv, html} = live(conn, ~p"/schedules/#{schedule.id}/edit")

      assert html =~ "Edit schedule"
      assert has_element?(lv, "#schedule-form")
    end

    test "edits an existing schedule's cron and returns to the table", %{conn: conn} do
      {:ok, schedule} = Scheduling.create(%{name: "Hourly", cron: "0 * * * *"})
      {:ok, lv, _html} = live(conn, ~p"/schedules/#{schedule.id}/edit")

      lv
      |> element("#schedule-form")
      |> render_submit(%{schedule: %{cron: "*/15 * * * *"}})

      assert_patch(lv, ~p"/schedules")
      assert Scheduling.get_schedule!(schedule.id).cron == "*/15 * * * *"
    end

    test "persists a per-schedule threshold override (inheritance still per-field)", %{conn: conn} do
      {:ok, schedule} = Scheduling.create(%{name: "Hourly", cron: "0 * * * *"})
      {:ok, lv, _html} = live(conn, ~p"/schedules/#{schedule.id}/edit")

      lv
      |> element("#schedule-form")
      |> render_submit(%{schedule: %{threshold_policy: "enabled", download: "100"}})

      assert_patch(lv, ~p"/schedules")

      refreshed = Scheduling.get_schedule!(schedule.id)
      assert refreshed.threshold_enabled == true
      assert refreshed.download == 100.0

      # The single threshold reader: override wins; unset fields inherit global.
      assert Scheduling.thresholds_for(refreshed) == %{
               enabled: true,
               download: 100.0,
               upload: 0.0,
               ping: 0.0
             }
    end
  end

  describe "delete" do
    test "deletes a schedule from the table", %{conn: conn} do
      {:ok, schedule} = Scheduling.create(%{name: "Gone", cron: "0 * * * *"})
      {:ok, lv, _html} = live(conn, ~p"/schedules")

      lv
      |> element("button[phx-click='delete'][phx-value-id='#{schedule.id}']")
      |> render_click()

      assert Scheduling.list_schedules() == []
      assert render(lv) =~ "Schedule deleted"
    end
  end
end
