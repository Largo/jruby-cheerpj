/*
 * CheerpJ overlay for JRuby 9.4's org.jruby.javasupport.binding.ConstantField
 * (EPL-2.0 / GPL-2.0 / LGPL-2.1, like JRuby). Same behaviour as upstream, plus one fallback.
 *
 * JRuby binds every public static final field of a Java class as a Ruby constant via
 * Field.get(null). The JDK serves static final fields through Unsafe.get<T>Volatile, and
 * CheerpJ 4.3 lacks those natives for char/short/float (and byte on Java 8), so merely
 * touching java.lang.Character, java.util.Locale, java.awt.Component (JFrame, Swing, ...)
 * raised UnsatisfiedLinkError. A MethodHandle getter reads the same field without the
 * volatile path, so we retry with it.
 */
package org.jruby.javasupport.binding;

import java.lang.invoke.MethodHandles;
import java.lang.reflect.Field;

import org.jruby.RubyModule;
import org.jruby.javasupport.JavaUtil;

public class ConstantField {
    final Field field;

    public ConstantField(Field field) { this.field = field; }

    void install(final RubyModule proxy) {
        final String name = field.getName();
        if (proxy.getConstantAt(name) == null) {
            final Object value;
            try {
                value = read(field);
            } catch (IllegalAccessException iae) {
                return; // if we can't read it, we don't set it
            }
            proxy.setConstant(name, JavaUtil.convertJavaToUsableRubyObject(proxy.getRuntime(), value));
        }
    }

    private static Object read(Field field) throws IllegalAccessException {
        try {
            return field.get(null);
        } catch (UnsatisfiedLinkError e) {
            try {
                return MethodHandles.publicLookup().unreflectGetter(field).invokeWithArguments(); // not invoke(): CheerpJ breaks signature-polymorphic calls
            } catch (IllegalAccessException iae) {
                throw iae;
            } catch (Throwable t) {
                throw e;
            }
        }
    }
}
