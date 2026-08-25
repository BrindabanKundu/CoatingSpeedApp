## Code/Plot with kivy.graphics not matplotlib ##
#################################################

import numpy as np

from kivy.app import App
from kivy.uix.gridlayout import GridLayout
from kivy.properties import ListProperty, NumericProperty
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.popup import Popup
from kivy.uix.widget import Widget
from kivy.graphics import Color, Ellipse, Line, Rectangle
from kivy.graphics.context_instructions import PushMatrix, PopMatrix, Rotate
from kivy.uix.label import Label
from kivy.uix.button import Button
from kivy.uix.textinput import TextInput


# ─────────────────────────────────────────────────────────────────────────────
# Plot widget
# ─────────────────────────────────────────────────────────────────────────────

class AnalysisPlotWidget(Widget):
    """
    Full analysis plot:
      - dashed fit curve
      - raw scatter (gray)
      - error bars (mean ± std per rpm)
      - target point (red square)
      - suggestion text
    """

    def __init__(self, results, target_Thickness, **kwargs):
        super().__init__(**kwargs)
        self.results          = results
        self.target_Thickness = target_Thickness
        self.bind(size=self._redraw, pos=self._redraw)

    # ── helpers ──────────────────────────────────────────────────────────────

    def _make_screen(self, x_min, x_range, y_min, y_range,
                     x0, y0, margin_l, margin_b, plot_w, plot_h):
        def to_screen(x, y):
            sx = x0 + margin_l + (x - x_min) / x_range * plot_w
            sy = y0 + margin_b + (y - y_min) / y_range * plot_h
            return sx, sy
        return to_screen

    def _redraw(self, *args):
        self.canvas.clear()
        for child in list(self.children):
            self.remove_widget(child)

        r   = self.results
        df  = r["df"]
        RPM_fit       = r["RPM_fit"]
        Thickness_fit = r["Thickness_fit"]
        df_stats      = r["df_stats"]
        slope         = r["slope"]
        intercept     = r["intercept"]
        target_T      = self.target_Thickness

        # ── target RPM calculation ────────────────────────────────────────────
        log_target_T   = np.log10(target_T)
        log_target_RPM = (log_target_T - intercept) / slope
        RPM_target     = float(10 ** log_target_RPM)

        RPM_min = float(df["RPM"].min())
        RPM_max = float(df["RPM"].max())
        T_data_min = float(min(df["Thickness"].min(), Thickness_fit.min(), target_T))
        T_data_max = float(max(df["Thickness"].max(), Thickness_fit.max(), target_T))

        # Axis tick range for the RPM axis (x-axis): round the min/max
        # (including the target RPM) to the nearest hundred, then pad
        # by 200 on each side. Ticks are drawn every 200 units.
        RPM_TICK_STEP = 200
        RPM_axis_min = round(min(RPM_min, RPM_target), -2) - RPM_TICK_STEP
        RPM_axis_max = round(max(RPM_max, RPM_target), -2) + RPM_TICK_STEP

        # Axis tick range for the Thickness axis (y-axis): round the
        # min/max (including the target Thickness) to the nearest ten,
        # then pad by 10 on each side. Ticks are drawn every 10 units.
        T_TICK_STEP = 10
        T_axis_min = round(T_data_min, -1) - T_TICK_STEP
        T_axis_max = round(T_data_max, -1) + T_TICK_STEP

        rpm_ticks = []
        v = RPM_axis_min
        while v <= RPM_axis_max:
            rpm_ticks.append(v)
            v += RPM_TICK_STEP

        t_ticks = []
        v = T_axis_min
        while v <= T_axis_max + 1e-9:
            t_ticks.append(v)
            v += T_TICK_STEP

        RPM_round = round(float(RPM_target), -2)
        if RPM_round <= RPM_min:
            RPM_suggestion = int(RPM_round - 200)
        elif RPM_round >= RPM_max:
            RPM_suggestion = int(RPM_round + 200)
        else:
            RPM_suggestion = int(RPM_round)

        # ── layout ────────────────────────────────────────────────────────────
        w, h   = self.size
        x0, y0 = self.pos
        margin_l, margin_r = 95, 20
        margin_b, margin_t = 75, 30
        plot_w = w - margin_l - margin_r
        plot_h = h - margin_b - margin_t

        rpm_range = (RPM_axis_max - RPM_axis_min) or 1
        t_range   = (T_axis_max   - T_axis_min)   or 1

        to_screen = self._make_screen(
            RPM_axis_min, rpm_range, T_axis_min, t_range,
            x0, y0, margin_l, margin_b, plot_w, plot_h
        )

        with self.canvas:

            # ── background ───────────────────────────────────────────────────
            Color(0.12, 0.12, 0.12, 1)
            Rectangle(pos=(x0 + margin_l, y0 + margin_b),
                      size=(plot_w, plot_h))

            # ── grid (one line per tick) ────────────────────────────────────────
            Color(0.25, 0.25, 0.25, 1)
            for rv in rpm_ticks:
                gx, _ = to_screen(rv, T_axis_min)
                Line(points=[gx, y0 + margin_b,
                              gx, y0 + margin_b + plot_h], width=0.8)
            for tv in t_ticks:
                _, gy = to_screen(RPM_axis_min, tv)
                Line(points=[x0 + margin_l, gy,
                              x0 + margin_l + plot_w, gy], width=0.8)

            # ── axes ─────────────────────────────────────────────────────────
            Color(0.6, 0.6, 0.6, 1)
            Line(points=[x0 + margin_l, y0 + margin_b,
                          x0 + margin_l, y0 + margin_b + plot_h], width=1.5)
            Line(points=[x0 + margin_l,          y0 + margin_b,
                          x0 + margin_l + plot_w, y0 + margin_b], width=1.5)

            # ── dashed fit curve ─────────────────────────────────────────────
            dash_len = 12    #8
            gap_len  = 2    #5
            pts = [to_screen(r, t) for r, t in zip(RPM_fit, Thickness_fit)]
            Color(0.7, 0.7, 0.7, 1)
            seg_pts = []
            seg_len = 0.0
            drawing = True
            for i in range(1, len(pts)):
                x1, y1 = pts[i - 1]
                x2, y2 = pts[i]
                dx, dy = x2 - x1, y2 - y1
                seg_total = (dx**2 + dy**2) ** 0.5
                traveled  = 0.0
                while traveled < seg_total:
                    remain = seg_total - traveled
                    need   = (dash_len - seg_len) if drawing else (gap_len - seg_len)
                    step   = min(need, remain)
                    frac   = traveled / seg_total
                    cx = x1 + dx * frac
                    cy = y1 + dy * frac
                    if drawing:
                        seg_pts.append(cx)
                        seg_pts.append(cy)
                    seg_len  += step
                    traveled += step
                    if seg_len >= (dash_len if drawing else gap_len):
                        if drawing and len(seg_pts) >= 4:
                            Line(points=seg_pts, width=1.5)
                        seg_pts = []
                        seg_len = 0.0
                        drawing = not drawing
            if drawing and len(seg_pts) >= 4:
                Line(points=seg_pts, width=1.5)

            # ── raw scatter (gray) ────────────────────────────────────────────
            dot_r = 20     #10
            for rpm_v, th_v in zip(df["RPM"], df["Thickness"]):
                sx, sy = to_screen(rpm_v, th_v)
                #Color(0.55, 0.55, 0.55, 0.7)
                Color(0.55, 0.55, 0.95, 0.7)
                Ellipse(pos=(sx - dot_r, sy - dot_r),
                        size=(dot_r * 2, dot_r * 2))

            # ── error bars (mean ± std) ───────────────────────────────────────
            cap = 6
            for rpm_v, mean_v, std_v in zip(df_stats["RPM"], df_stats["mean"], df_stats["std"]):
                mx, my   = to_screen(rpm_v, mean_v)
                _, y_top = to_screen(rpm_v, mean_v + std_v)
                _, y_bot = to_screen(rpm_v, mean_v - std_v)

                # vertical error line
                Color(0.75, 0.75, 0.75, 1)
                Line(points=[mx, y_bot, mx, y_top], width=1.5)
                # caps
                Line(points=[mx - cap, y_top, mx + cap, y_top], width=1.5)
                Line(points=[mx - cap, y_bot, mx + cap, y_bot], width=1.5)
                # mean square marker
                sq = 7
                Color(0.5, 0.5, 0.5, 1)
                Rectangle(pos=(mx - sq, my - sq), size=(sq * 2, sq * 2))
                Color(0.85, 0.85, 0.85, 1)
                Line(rectangle=(mx - sq, my - sq, sq * 2, sq * 2), width=1)

            # ── target point (red square) ─────────────────────────────────────
            tx, ty = to_screen(RPM_target, target_T)
            sq = 12      #8
            Color(0.9, 0.15, 0.15, 0.85)
            Rectangle(pos=(tx - sq, ty - sq), size=(sq * 2, sq * 2))
            Color(1, 1, 1, 1)
            Line(rectangle=(tx - sq, ty - sq, sq * 2, sq * 2), width=1)

        # ── axis tick labels (every other tick) ─────────────────────────────────
        for rv in rpm_ticks[::2]:
            sx, _ = to_screen(rv, T_axis_min)
            self.add_widget(Label(text=str(int(rv)),
                                  pos=(sx - 25, y0 + margin_b - 40),
                                  size=(50, 20), font_size="13sp",
                                  color=(1, 1, 1, 1)))

        for tv in t_ticks[::2]:
            _, sy = to_screen(RPM_axis_min, tv)
            self.add_widget(Label(text=str(int(tv)),
                                  pos=(x0 + 25, sy - 10),
                                  size=(55, 20), font_size="13sp",
                                  color=(1, 1, 1, 1)))

        # ── axis titles ───────────────────────────────────────────────────────
        self.add_widget(Label(
            text="Coating speed [rpm]",
            pos=(x0 + margin_l + plot_w / 2 - 60, y0 + 2),
            size=(140, 20), font_size="16sp", color=(1, 1, 1, 1)
        ))

        # Y-axis title rotated 90° anti-clockwise
        lbl_w, lbl_h = 100, 20
        lbl_cx = x0 + lbl_h / 2               # centre x (near left edge)
        lbl_cy = y0 + margin_b + plot_h / 2   # centre y (mid plot height)
        rotated_lbl = Label(
            text="Thickness [nm]",
            size=(lbl_w, lbl_h),
            font_size="16sp",
            color=(1, 1, 1, 1),
        )
        rotated_lbl.pos = (lbl_cx - lbl_w / 2, lbl_cy - lbl_h / 2)
        with rotated_lbl.canvas.before:
            PushMatrix()
            Rotate(angle=90, origin=(lbl_cx, lbl_cy))
        with rotated_lbl.canvas.after:
            PopMatrix()
        self.add_widget(rotated_lbl)

        # ── suggestion text ───────────────────────────────────────────────────
        if RPM_min <= RPM_target <= RPM_max:
            msg   = f"Coating speed = {int(RPM_target)} rpm\n\nThickness = {int(target_T)} nm"
            tcolor = (1, 1, 1, 1)
        else:
            msg   = (f"Please coat another substrate\n"
                     f"with {RPM_suggestion} rpm\n\n"
                     f"Thickness = {int(target_T)} nm")
            tcolor = (1, 0.25, 0.25, 1)

        self.add_widget(Label(
            text=msg,
            pos=(x0 + margin_l + plot_w * 0.42, y0 + margin_b + plot_h * 0.55),
            size=(plot_w * 0.53, plot_h * 0.42),
            font_size="18sp",
            halign="right", valign="top",
            color=tcolor,
            text_size=(plot_w * 0.53, plot_h * 0.42),
        ))


# ─────────────────────────────────────────────────────────────────────────────
# Main layout
# ─────────────────────────────────────────────────────────────────────────────

class TableLayout(BoxLayout):
    table_data     = ListProperty([])
    selected_index = NumericProperty(-1)

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.data = []

    # ── slider <-> text input sync ──────────────────────────────────────────

    def on_rpm_slider(self, value):
        self.ids.rpm_input.text = str(int(value))

    def on_rpm_text(self, text):
        try:
            val = int(text)
        except ValueError:
            self.ids.rpm_input.text = str(int(self.ids.rpm_slider.value))
            return
        val = max(self.ids.rpm_slider.min, min(self.ids.rpm_slider.max, val))
        self.ids.rpm_slider.value = val
        self.ids.rpm_input.text = str(val)

    def on_th_slider(self, value):
        self.ids.th_input.text = str(int(value))

    def on_th_text(self, text):
        try:
            val = int(text)
        except ValueError:
            self.ids.th_input.text = str(int(self.ids.th_slider.value))
            return
        val = max(self.ids.th_slider.min, min(self.ids.th_slider.max, val))
        self.ids.th_slider.value = val
        self.ids.th_input.text = str(val)

    # ── data entry ───────────────────────────────────────────────────────────

    def add_entry(self):
        rpm = int(self.ids.rpm_slider.value)
        th  = int(self.ids.th_slider.value)
        self.data.append((rpm, th))
        self.refresh_table()

    def update_values(self):
        rpm = int(self.ids.rpm_slider.value)
        th  = int(self.ids.th_slider.value)
        if self.selected_index >= 0:
            self.data[self.selected_index] = (rpm, th)
        elif self.data:
            self.data[-1] = (rpm, th)
        else:
            self.data.append((rpm, th))
        self.refresh_table()

    def delete_selected(self):
        if self.selected_index >= 0:
            self.data.pop(self.selected_index)
            self.selected_index = -1
            self.refresh_table()

    def select_row(self, index):
        self.selected_index = index
        rpm, th = self.data[index]
        self.ids.rpm_slider.value = rpm
        self.ids.th_slider.value  = th
        self.refresh_table()

    def refresh_table(self):
        rv_data = []
        for i, (rpm, th) in enumerate(self.data):
            rv_data.append({
                "rpm_text": str(rpm),
                "th_text":  str(th),
                "index":    i,
                "selected": self.selected_index == i,
            })
        self.table_data = rv_data

    # ── analysis ─────────────────────────────────────────────────────────────

    def get_dataframe(self):
        """Return current data as {'RPM': ndarray, 'Thickness': ndarray}."""
        if not self.data:
            return {"RPM": np.array([]), "Thickness": np.array([])}
        rpm, th = zip(*self.data)
        return {"RPM": np.array(rpm, dtype=float),
                "Thickness": np.array(th, dtype=float)}

    def analyse(self):
        """Run log-log fit and compute stats. Returns results dict."""
        data = self.get_dataframe()
        RPM, Thickness = data["RPM"], data["Thickness"]

        # drop entries where Thickness is NaN
        mask = ~np.isnan(Thickness)
        RPM, Thickness = RPM[mask], Thickness[mask]

        logRPM       = np.log10(RPM)
        logThickness = np.log10(Thickness)
        coeffs    = np.polyfit(logRPM, logThickness, 1)
        slope, intercept = coeffs[0], coeffs[1]

        RPM_new          = np.linspace(RPM.min(), RPM.max(), 50)
        Thickness_new    = 10 ** (slope * np.log10(RPM_new) + intercept)

        # group by RPM: mean/std of Thickness per unique RPM value
        unique_rpm = np.unique(RPM)
        means = np.array([Thickness[RPM == r].mean() for r in unique_rpm])
        stds  = np.array([
            Thickness[RPM == r].std(ddof=1) if np.count_nonzero(RPM == r) > 1 else 0.0
            for r in unique_rpm
        ])

        return {
            "df":            {"RPM": RPM, "Thickness": Thickness},
            "slope":         slope,
            "intercept":     intercept,
            "RPM_fit":       RPM_new,
            "Thickness_fit": Thickness_new,
            "df_stats":      {"RPM": unique_rpm, "mean": means, "std": stds},
        }

    # ── UI actions ────────────────────────────────────────────────────────────

    def show_plot(self):
        """Simple scatter plot of raw data."""
        if not self.data:
            self._alert("No Data", "Add some data points first.")
            return

        class RawScatter(Widget):
            def __init__(self, data, **kw):
                super().__init__(**kw)
                self._data = data
                self.bind(size=self._draw, pos=self._draw)

            def _draw(self, *a):
                self.canvas.clear()
                for c in list(self.children):
                    self.remove_widget(c)
                w, h   = self.size
                x0, y0 = self.pos
                ml, mr, mb, mt = 95, 20, 75, 20
                pw, ph = w - ml - mr, h - mb - mt
                rpms = [d[0] for d in self._data]
                ths  = [d[1] for d in self._data]
                rmin, rmax = min(rpms), max(rpms)
                tmin, tmax = min(ths),  max(ths)

                # Axis tick range: round min/max to the nearest hundred
                # (rpm) / ten (thickness), then pad by 200 / 10.
                RPM_TICK_STEP = 200
                r_axis_min = round(rmin, -2) - RPM_TICK_STEP
                r_axis_max = round(rmax, -2) + RPM_TICK_STEP

                T_TICK_STEP = 10
                t_axis_min = round(tmin, -1) - T_TICK_STEP
                t_axis_max = round(tmax, -1) + T_TICK_STEP

                r_ticks = []
                v = r_axis_min
                while v <= r_axis_max:
                    r_ticks.append(v)
                    v += RPM_TICK_STEP

                t_ticks = []
                v = t_axis_min
                while v <= t_axis_max + 1e-9:
                    t_ticks.append(v)
                    v += T_TICK_STEP

                rr = (r_axis_max - r_axis_min) or 1
                tr = (t_axis_max - t_axis_min) or 1
                def ts(r, t):
                    return (x0 + ml + (r - r_axis_min) / rr * pw,
                            y0 + mb + (t - t_axis_min) / tr * ph)
                with self.canvas:
                    Color(0.12, 0.12, 0.12, 1)
                    Rectangle(pos=(x0+ml, y0+mb), size=(pw, ph))
                    Color(0.25, 0.25, 0.25, 1)
                    for rv in r_ticks:
                        gx, _ = ts(rv, t_axis_min)
                        Line(points=[gx, y0+mb, gx, y0+mb+ph], width=0.8)
                    for tv in t_ticks:
                        _, gy = ts(r_axis_min, tv)
                        Line(points=[x0+ml, gy, x0+ml+pw, gy], width=0.8)
                    Color(0.6, 0.6, 0.6, 1)
                    Line(points=[x0+ml, y0+mb, x0+ml, y0+mb+ph], width=1.5)
                    Line(points=[x0+ml, y0+mb, x0+ml+pw, y0+mb], width=1.5)
                    dot_r = 20      #10
                    for rpm, th in self._data:
                        sx, sy = ts(rpm, th)
                        Color(0.15, 0.47, 0.9, 1)
                        Ellipse(pos=(sx-dot_r, sy-dot_r),
                                size=(dot_r*2, dot_r*2))
                        Color(1, 1, 1, 1)
                        Line(circle=(sx, sy, dot_r), width=1)
                for rv in r_ticks[::2]:
                    sx, _ = ts(rv, t_axis_min)
                    self.add_widget(Label(text=str(int(rv)),
                                         pos=(sx-20, y0+mb-40),
                                         size=(40,20), font_size="13sp",
                                         color=(1,1,1,1)))
                for tv in t_ticks[::2]:
                    _, sy = ts(r_axis_min, tv)
                    self.add_widget(Label(text=str(int(tv)),
                                         pos=(x0+25, sy-10),
                                         size=(50,20), font_size="13sp",
                                         color=(1,1,1,1)))
                self.add_widget(Label(text="Coating Speed [rpm]",
                    pos=(x0+ml+pw/2-20, y0+2), size=(40,20),
                    font_size="16sp", color=(1,1,1,1)))
                lbl_w, lbl_h = 100, 20
                lbl_cx = x0 + lbl_h / 2
                lbl_cy = y0 + mb + ph / 2
                rlbl = Label(text="Thickness [nm]", size=(lbl_w, lbl_h),
                             font_size="16sp", color=(1, 1, 1, 1))
                rlbl.pos = (lbl_cx - lbl_w / 2, lbl_cy - lbl_h / 2)
                with rlbl.canvas.before:
                    PushMatrix()
                    Rotate(angle=90, origin=(lbl_cx, lbl_cy))
                with rlbl.canvas.after:
                    PopMatrix()
                self.add_widget(rlbl)

        content = BoxLayout(orientation="vertical", spacing=8, padding=10)
        content.add_widget(RawScatter(data=self.data, size_hint=(1, 1)))
        btn = Button(text="Close", color= (0, 0, 0, 1), bold= True, size_hint=(1, None), height="44dp", 
                    #background_color=(0.2, 0.5, 1, 1)
                    background_normal= '',
                    background_color=(1, 0.98, 0.71, 1)
                      )
        content.add_widget(btn)
        popup = Popup(title="Coating Speed vs Thickness", content=content,
                      size_hint=(0.95, 0.85),
                      title_size="16sp")
        btn.bind(on_press=popup.dismiss)
        popup.open()

    def show_target_input(self):
        """Popup to enter target Thickness, then run full analysis plot."""
        if len(self.data) < 2:
            self._alert("Not Enough Data",
                        "Add at least 2 data points before calculating.")
            return

        content = BoxLayout(orientation="vertical", spacing=12, padding=20)
        content.add_widget(Label(text="Enter target Thickness [nm]:",
                                 size_hint_y=None, height="30dp"))
        entry = TextInput(hint_text="e.g. 100", multiline=False,
                          input_filter="float",
                          size_hint_y=None, height="44dp")
        content.add_widget(entry)

        btn_row = BoxLayout(size_hint_y=None, height="44dp", spacing=10)
        btn_ok     = Button(text="Calculate & Plot",
                            background_normal= '',
                            background_color=(0.2, 0.6, 0.3, 1)
                            )
        btn_cancel = Button(text="Cancel",
                            background_normal= '',
                            background_color=(0.5, 0.5, 0.5, 1)
                            )
        btn_row.add_widget(btn_ok)
        btn_row.add_widget(btn_cancel)
        content.add_widget(btn_row)

        popup = Popup(title="Spin Calculator", content=content,
                      size_hint=(0.85, 0.45),
                      pos_hint= {'center_x': 0.5, 'center_y': 0.75}
                      )

        def on_calculate(instance):
            try:
                target_T = float(entry.text)
                if target_T <= 0:
                    raise ValueError
            except ValueError:
                entry.hint_text = "Please enter a valid positive number"
                return
            popup.dismiss()
            self._show_analysis_plot(target_T)

        btn_ok.bind(on_press=on_calculate)
        btn_cancel.bind(on_press=popup.dismiss)
        entry.bind(on_text_validate=on_calculate)   # keyboard Enter key
        popup.open()

    def _show_analysis_plot(self, target_T):
        try:
            results = self.analyse()
        except Exception as e:
            self._alert("Analysis Error", str(e))
            return

        content = BoxLayout(orientation="vertical", spacing=8, padding=10)
        plot = AnalysisPlotWidget(results=results,
                                  target_Thickness=target_T,
                                  size_hint=(1, 1))
        content.add_widget(plot)    
        btn = Button(text="Close", color= (0, 0, 0, 1), bold= True, size_hint=(1, None), height="44dp", 
                    #background_color=(0.2, 0.5, 1, 1)
                    background_normal= '',
                    background_color=(1, 0.98, 0.71, 1)
                      )
        content.add_widget(btn)
        #popup = Popup(title=f"Analysis — Target: {int(target_T)} nm",
        #              content=content, size_hint=(0.97, 0.92))
        popup = Popup(title=f"Analysis — Target: {int(target_T)} nm",
                      content=content, size_hint=(0.97, 0.92),
                      title_size="16sp")
                      
        btn.bind(on_press=popup.dismiss)
        popup.open()

    def _alert(self, title, msg):
        popup = Popup(title=title,
                      content=Label(text=msg, halign="center"),
                      size_hint=(0.75, 0.3))
        popup.open()


# ─────────────────────────────────────────────────────────────────────────────

class TableApp(App):
    def build(self):
        return TableLayout()


if __name__ == "__main__":
    TableApp().run()
