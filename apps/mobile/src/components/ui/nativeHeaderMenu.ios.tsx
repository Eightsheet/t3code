import type { MenuAction } from "@react-native-menu/menu";
import { Platform, Pressable } from "react-native";
import { SymbolView, type AppSymbolName } from "./AppSymbol";
import { Menu } from "./Menu";
import { findAppBarMenuItem, menuActionsFromAppBarItems } from "./menuActionItems";
import { Toolbar } from "./Toolbar";

import type { AppBarMenu, AppBarMenuItem } from "./AppBar.types";

/**
 * iOS 27 closes a bar button's menu by morphing it back into the button, which hides the
 * button behind a drifting blob and then pops it back in. Bar menus drawn by the app open
 * through the patched `Menu`, which fades out on close instead.
 */
export const APP_DRAWN_BAR_MENUS =
  Platform.OS === "ios" && Number.parseInt(String(Platform.Version), 10) >= 27;

/** A bar button that opens `actions`; the system bar still draws its glass background. */
export function BarMenuButton(props: {
  readonly title: string;
  readonly accessibilityLabel?: string;
  readonly icon: AppSymbolName;
  readonly actions: MenuAction[];
  readonly onSelect: (id: string) => void;
  readonly disabled?: boolean;
}) {
  return (
    <Menu
      title={props.title}
      actions={props.actions}
      onPressAction={({ nativeEvent }) => props.onSelect(nativeEvent.event)}
    >
      <Pressable
        accessibilityRole="button"
        accessibilityLabel={props.accessibilityLabel ?? props.title}
        accessibilityState={{ disabled: Boolean(props.disabled) }}
        disabled={props.disabled}
        className="size-11 items-center justify-center rounded-full"
      >
        <SymbolView
          name={props.icon}
          size={20}
          tintColorClassName={props.disabled ? "accent-icon-subtle" : "accent-foreground"}
        />
      </Pressable>
    </Menu>
  );
}

const STATUS_ACTION_ID = "__app-bar-menu-status";

function renderMenuItems(items: ReadonlyArray<AppBarMenuItem>) {
  return items.map((item) =>
    "items" in item ? (
      <Toolbar.Menu key={item.id} title={item.title} icon={item.icon} inline={item.inline}>
        {renderMenuItems(item.items)}
      </Toolbar.Menu>
    ) : (
      <Toolbar.MenuAction
        key={item.id}
        icon={item.icon}
        subtitle={item.subtitle}
        disabled={item.disabled}
        destructive={item.destructive}
        isOn={item.selected}
        onPress={item.onPress}
      >
        {item.title}
      </Toolbar.MenuAction>
    ),
  );
}

export function createNativeHeaderMenu(menu: AppBarMenu) {
  if (APP_DRAWN_BAR_MENUS) {
    return (
      <Toolbar.Custom key={menu.title}>
        <BarMenuButton
          title={menu.title}
          icon={menu.icon}
          actions={[
            ...(menu.status
              ? [{ id: STATUS_ACTION_ID, title: menu.status, attributes: { disabled: true } }]
              : []),
            ...menuActionsFromAppBarItems(menu.items),
          ]}
          onSelect={(id) => findAppBarMenuItem(menu.items, id)?.onPress()}
        />
      </Toolbar.Custom>
    );
  }
  return (
    <Toolbar.Menu
      key={menu.title}
      title={menu.title}
      accessibilityLabel={menu.title}
      icon={typeof menu.icon === "string" ? menu.icon : menu.icon.ios}
      separateBackground={menu.separateBackground ?? true}
    >
      {menu.status ? <Toolbar.Label>{menu.status}</Toolbar.Label> : null}
      {renderMenuItems(menu.items)}
    </Toolbar.Menu>
  );
}
