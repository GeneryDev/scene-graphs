# Scene Graphs (Godot 4.7+)
The Scene Graphs plugin provides an alternative way to view and edit your Godot scenes, through a configurable graph view that can show connections between nodes -- whether they're signals, node references, or something else entirely.

This plugin is also moddable, letting you add functionality to serve the particular needs of your project without editing plugin files directly, if necessary.

<img width="1972" height="1144" alt="Godot_v4 7 1-stable_mono_win64_tYoFqzto46" src="https://github.com/user-attachments/assets/86a12ad2-289e-4616-a7a3-b7d387f907f8" />

## Features
### Method-Signal Connections
* The scene graph can show connected signals and methods between nodes.
* Connect/disconnect signals by dragging connections between ports.
* Edit the connection flags and bound arguments in the inspector by selecting the arrow in the middle of the connection line (including for multiple connections at once!)

<img width="1320" height="839" alt="image" src="https://github.com/user-attachments/assets/3f4533a3-a95a-4747-850a-8b87f4002aac" />

### Node References
* The scene graph can show relationships between nodes given by properties of type NodePath, or of Node-derived types.
* Set/unset NodePath/Node properties by dragging connections between ports.

<img width="1897" height="1210" alt="image" src="https://github.com/user-attachments/assets/d1b397c1-796a-40b0-acef-2a2bd72164a3" />

### Property Inspectors
* The scene graph can also show inspectors for properties of nodes, directly in the node graph.

<img width="1450" height="1139" alt="image" src="https://github.com/user-attachments/assets/2562d3c2-b7cb-473d-a0c7-18bab89b0a0f" />

### Connection Handles
* Connection lines on the graph show handles: small elements in the middle that you can select and drag to redirect the connection line. Useful for graphs that get too complex and tangled.
* Signal connections also override handles with more functionality, showing icons corresponding to the connection flags.

<img width="1364" height="1006" alt="Godot_v4 7 1-stable_mono_win64_RiFWVxO1SJ" src="https://github.com/user-attachments/assets/dec84150-2316-4d37-acb1-09b4240cc579" />

### Views
* Save multiple views, for each different way you want to look at your scene.
* Each view has its own feature configuration (for each of the sections above).
* You can always manually add nodes to the view by dragging them in from the Scene tree, and members by pressing the Manage Object View button.
* But to do that automatically, each view has its own set of "view rules" that determine how the view populates itself, such as adding all nodes with method-signal connections.
* Views can be either local (to one scene) or global (across all scenes), so you can use common view configurations in multiple scenes.

<img width="722" height="532" alt="Godot_v4 7 1-stable_mono_win64_wxJ1JFTO8h" src="https://github.com/user-attachments/assets/e50d7131-3014-4470-bc05-1b89b22abf8a" />

### Moddable
I know signals and node references aren't the only things you may want to see in a scene graph, so this plugin was built with moddability in mind. In fact, most of the features listed above are built as hooks -- the core of this plugin is a rather small, featureless GraphEdit with a View Manager UI to configure hooks. In short, hooks are scripts that get initialized alongside the scene graph editor, which can opt-in to any number of capabilities, such as configuring a view rule, adding a new port type, inserting elements into the standard object GraphNode, etc.

[These modding capabilities are documented extensively in the wiki.](https://github.com/GeneryDev/scene-graphs/wiki/Modding)

## Installation
1. Download the plugin into your Godot project. Its location should be `addons/scene-graphs`.
2. Enable in Project Settings -> Plugins.
3. Check out the plugin's settings at: Project Settings -> General -> Scene Graphs -> Editor.
   You may choose whether to use this plugin as a main screen plugin or as a dock panel.

## Future Improvements
* Live updating of graph nodes when nodes are added, removed or renamed in the scene.
* Live updating of connections when changes are made outside the scene graph (for the time being, there's a reload button on the toolbar next to the view dropdown)
* Better type validation for Node Reference connections.
* Better node arranging algorithm (the default one is serviceable, but generates too many unnecessary line crossings.
* Support for Resource graph nodes? 👀

## Disclaimers
No AI was used in the making of this plugin.
