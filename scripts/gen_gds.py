import klayout.db as db

# Create layout
layout = db.Layout()
layout.dbu = 0.001

# Create top cell
top = layout.create_cell("tt_um_multi_stage_processor")

# Create simple geometry (dummy box)
layer = layout.layer(1, 0)
top.shapes(layer).insert(db.Box(0, 0, 10000, 10000))

# Ensure output folder exists
import os
os.makedirs("gds", exist_ok=True)

# Write GDS
layout.write("gds/tt_um_multi_stage_processor.gds")
