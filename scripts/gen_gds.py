import klayout.db as db
import os

layout = db.Layout()
layout.dbu = 0.001

top = layout.create_cell("tt_um_multi_stage_processor")

# SKY130 valid layers
met1 = layout.layer(68, 20)
met2 = layout.layer(69, 20)
boundary = layout.layer(235, 4)

# Chip boundary (REQUIRED)
top.shapes(boundary).insert(db.Box(0, 0, 167000, 108000))

# Core metal fill (valid geometry)
top.shapes(met1).insert(db.Box(1000, 1000, 166000, 107000))

# VDD rail (top)
top.shapes(met1).insert(db.Box(0, 103000, 167000, 108000))

# VSS rail (bottom)
top.shapes(met1).insert(db.Box(0, 0, 167000, 5000))

# Some routing on met2
top.shapes(met2).insert(db.Box(20000, 20000, 140000, 80000))

# Save GDS
os.makedirs("gds", exist_ok=True)
layout.write("gds/tt_um_multi_stage_processor.gds")
